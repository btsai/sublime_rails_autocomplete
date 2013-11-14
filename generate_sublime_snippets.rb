# -*- coding: utf-8 -*-
# MAC ONLY!!!
# this script will scan all of the specified folders/files for class/module names and method names
# and output a sublime-completions file for the found class and method names.
# method names with arguments will be marked up with placeholders so you can tab to them.

begin

  if RUBY_VERSION =~ /1.9/
    Encoding.default_external = Encoding::UTF_8
    Encoding.default_internal = Encoding::UTF_8
  end

  require 'fileutils'
  require 'rubygems'
  require 'json'

  module Sublime
    class GenerateCompletes

      def run(args)
        settings, output_path = args
        settings = JSON.parse(settings)

        class_names, constant_names, method_names = FileParser.new(settings).find_definitions
        AutoCompleteFileGenerator.new.output(class_names, constant_names, method_names, output_path)

        puts "> Saved Rails autocomplete file to #{output_path}"
        puts "  #{class_names.size} class names."
        puts "  #{constant_names.size} constants."
        print "  #{method_names.size} methods."
      end

    end

    class FileParser
      attr_reader :settings

      def initialize(settings)
        @settings = settings
      end

      def find_definitions
        class_parser = ClassParser.new(settings)
        constant_parser = ConstantParser.new(settings)
        method_parser = MethodParser.new(settings)

        fetch_files.each do |file|
          class_parser.parse_file(file)
          constant_parser.parse_file(file)
          method_parser.parse_file(file)
        end

        [class_parser.sorted, constant_parser.sorted, method_parser.sorted]
      end

      def fetch_files
        files = []
        {:add => settings['source_paths'], :remove => settings['exclude_paths']}.each do |action, paths|
          paths.each do |path|
            path = File.join(path, '**/*.rb') unless path.match(/[a-zA-Z]\.rb/)
            found_files = Dir.glob(path)
            action == :add ? files += found_files : files -= found_files
          end
        end
        files
      end

    end

    class LineParser
      attr_reader :settings

      def initialize(settings)
        @settings = settings
        @triggers = []
        @snippets = []
      end

      def parse_file(file)
        @file = file
        @private = false
        @in_module_scope = false

        File.readlines(@file).each_with_index do |line, line_num|
          line_num += 1  # adjust for 0 index

          # track if in private/protected area of code and ignore anything there.
          # using private so that we can debug in each of the definition methods.
          if line.strip == 'private' || line.strip == 'protected'
            @private = true
          elsif line.strip == 'public'
            @private = false
          end
          parse_line(line, line_num)
        end
      end

      def add_snippet(snippet_data)
        return if @triggers.include?(snippet_data.trigger)
        @triggers << snippet_data.trigger
        @snippets << snippet_data
      end

      def sorted
        @snippets.sort{ |a,b| a[0] <=> b[0] }.uniq
      end


      def is_comment?(line)
        line.match(/^\s*#/)
      end

    end

    class ClassParser < LineParser

      # list of bogus hits
      def ignorable_class_names
        [
          '<',        # from 'class << self'
        ]
      end

      def parse_line(line, line_num)
        return unless class_name = class_name_in_line(line)

        # filter out unneeded class/module names
        return if ignorable_class_names.include?(class_name)
        return if settings['exclude_class_names'].include?(class_name)
        return if settings['exclude_class_regex'] &&
                  !settings['exclude_class_regex'].empty? &&
                  class_name.match(settings['exclude_class_regex'])

        snippet_data = SnippetData.new(class_name, nil, @file, line_num)
        snippet_data.snippet = class_name if @in_module_scope
        add_snippet(snippet_data)

        # this will have problems where multiple classes are defined in the same file.
        # can't easily get the ending 'end' to know when we're out of module scope.
        # so this just happens once per file. oh well.
        @in_module_scope = true
      end

      def class_name_in_line(line)
        # looking for the word 'class' or 'module' in an uncommented line
        match = line.match(/(^|\s)
                            (class|module)\s
                            (.+?)       # class or module name
                            ($|\s|\<)      # end of line or else end of class name, before parent class declaration
                           /x)

        return unless match && !is_comment?(line)
        match[3].strip
      end

    end

    class ConstantParser < LineParser

      def parse_line(line, line_num)
        return unless constant = constant_in_line(line)

        snippet_data = SnippetData.new(constant, nil, @file, line_num)
        model_name = snippet_data.model_name
        snippet_data.trigger = "#{model_name}::#{constant}"
        add_snippet(snippet_data)
      end

      def constant_in_line(line)
        match = line.match(/([A-Z_]+) # constant name
                            (\s*)     # can have zero or more space
                            =         # must have equals sign to ensure definition
                            [^=]      # ignore equality check
                           /x)
        return unless match && !is_comment?(line)
        match[1].strip
      end

    end

    class MethodParser < LineParser

      def parse_line(line, line_num)
        return unless method_line = line_with_method(line)

        method_name, args_string = method_and_args(method_line)
        return if settings['exclude_method_names'].include?(method_name)
        return if settings['exclude_method_regex'] &&
                  !settings['exclude_method_regex'].empty? &&
                  method_name.match(settings['exclude_method_regex'])

        snippet_text = args_string.nil? ?
                       method_name :
                       snippet_with_args(method_name, args_string)
        add_snippet(SnippetData.new(method_name, snippet_text, @file, line_num))
      end

      def line_with_method(line)
        # looking for 'def' in a line, including the method and args
        match = line.match(/(^|\s)
                            def\s
                            (.+?)   # method name plus args
                            ($|;)   # end of line or else end of def (for single line error class definitions)
                           /x)
        return unless match && !is_comment?(line)
        match[2].gsub('self.', '').strip
      end

      def method_and_args(method_line)
        # pulling out the method name, as well as args, if they exist
        match = method_line.match(/^
                                  (.+?)           # method name
                                  (
                                    \((.+?)\) |   # args
                                    $             # or end of method, no args
                                  )/x)
        [match[1], match[3]]
      end

      def snippet_with_args(method_name, args_string)
        # add markers for each of the args
        args = args_string.split(',').map(&:strip)
        arg_defs = []
        args.each_with_index { |arg, i| arg_defs << "${#{i + 1}:#{arg}}" }
        method_name + "(#{arg_defs.join(', ')})"
      end

    end

    class SnippetData < Struct.new(:trigger, :snippet, :file, :line)

      def to_autocomplete
        # methods without args can also just be plain text, but with args needs to be a json object
        if snippet.nil?
          # if there are no arguments, the snippet = trigger, which can then just be output as the string itself
          "\"#{escape_quotes(trigger)}\""
        elsif trigger == snippet
          # no arguments but this is a namespaced thing, so add the description
          snippet_as_json
        else
          # if there are arguments, output a json object containing both the trigger and snippet
          snippet_as_json
        end
      end

      def model_name
        filename = File.basename(file, '.rb')
        model_name = filename.sub(/^[a-z\d]*/) {  $&.capitalize }
        model_name = model_name.gsub(/(?:_|(\/))([a-z\d]*)/) { "#{$1}#{$2.capitalize}" }
      end

      private

      def snippet_as_json
        %Q({ "trigger": "#{trigger_with_model_name}", "contents": "#{escape_quotes(snippet)}" })
      end

      def trigger_with_model_name
        "#{trigger}\t#{model_name}"
      end

      def escape_quotes(text)
        text.dup.gsub('"', '\"')
      end

    end

    class AutoCompleteFileGenerator

      def output(class_names, constant_names, method_names, output_path)
        delete_file(output_path)

        json = build_json(class_names, constant_names, method_names)
        File.open(output_path, 'w') { |f| f.write(json) }
      end

      def delete_file(output_path)
        File.delete(output_path) if File.exists?(output_path)
      end

      private

      def build_json(class_names, constant_names, method_names)
        <<-JSON
{
  "scope": "source.ruby.rails",
  "completions": [
    #{class_names.map(&:to_autocomplete).join(",\n    ")},
    #{constant_names.map(&:to_autocomplete).join(",\n    ")},
    #{method_names.map(&:to_autocomplete).join(",\n    ")}
  ]
}
        JSON
      end

    end

  end

  Sublime::GenerateCompletes.new.run(ARGV)

# outputting to stdout so that sublime can display in the console.
rescue LoadError => err
  puts "RUBY ERROR: #{err.message}"
  puts err.backtrace
rescue => err
  puts "RUBY ERROR: #{err.message}"
  puts err.backtrace
end
