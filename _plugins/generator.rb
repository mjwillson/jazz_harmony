require "jekyll"
require "securerandom"

module Jekyll
  class LilyPondGenerator < Generator
    priority :lowest
    
    def generate(site)
      setup_lily_directories
      remove_stale_lily_image_references(site)
      (site.pages + site.docs_to_write).each do |doc|
        next unless /md|markdown/.match?(doc.extname)
        doc.content = convert(site, doc.content)
      end
    end

    private
    
    def convert(site, content)
      lily_snippets = content.scan(/```lilypond.+?```\n/m)
      lily_snippets.each do |snippet|
        # Write out .ly file:
        code = snippet.gsub(/```lilypond\n/, "").gsub(/```\n/, "")
        base_filename = SecureRandom.uuid
        lily_filename = "#{base_filename}.ly"
        open(lily_filename, 'w') do |f|
          f.puts <<-END
% Disable page footer
\\paper { oddFooterMarkup = ##f }
END
          f.puts(code)
        end

        # Run lilypond on it:
        system("lilypond", "--png", lily_filename)
        system("rm", lily_filename)

        # Trim the resulting png file and move it to lily_images/
        png_filename = "#{base_filename}.png"
        system("convert", png_filename, "-trim", "lily_images/#{png_filename}")
        system("rm", png_filename)
        site.static_files << Jekyll::StaticFile.new(
          site, site.source, "lily_images", png_filename)

        # Handle midi file, if it was output (will only happen if snippet had
        # a \midi section inside \score):
        midi_filename = "#{base_filename}.midi"
        has_audio = File.exists?(midi_filename)
        if has_audio
          # Convert to WAV then MP3:
          wav_filename = "#{base_filename}.wav"
          mp3_filename = "#{base_filename}.mp3"
          system("fluidsynth", "-ni", "/opt/local/share/sounds/sf2/FluidR3_GM.sf2",
                 midi_filename, "-F", wav_filename, "-r", "44100")
          system("lame", "-V2", "-m", "m", wav_filename, mp3_filename)
          system("rm", midi_filename)
          system("rm", wav_filename)
          system("mv", mp3_filename, "lily_audio/")
          site.static_files << Jekyll::StaticFile.new(
            site, site.source, "lily_audio", mp3_filename)
        end

        baseurl = site.config["baseurl"].to_s.chomp("/")
        replacement = "![](#{baseurl}/lily_images/#{png_filename})\n"
        if has_audio
          replacement += <<-END
<div>
  <audio controls="controls">
    <source type="audio/mp3" src="#{baseurl}/lily_audio/#{mp3_filename}">
    <p>Your browser does not support the audio element.</p>
  </audio>
</div>
END
        end
        content.gsub!(snippet, replacement)
      end
      content
    end

    def setup_lily_directories
      system("mkdir", "-p", "lily_images/")
      system("mkdir", "-p", "lily_audio/")
    end

    def remove_stale_lily_image_references(site)
      site.static_files.reject! do |static_file|
        /lily_(images|audio)\/.*\.(svg|png|mp3)/.match?(static_file.path)
      end
    end
  end
end
