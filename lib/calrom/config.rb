module Calrom
  class Config
    DEFAULT_DATA = CR::Data::GENERAL_ROMAN_ENGLISH
    DEFAULT_LOCALE = :en

    def initialize
      self.today = Date.today
      self.date_range = Month.new(today.year, today.month)
      self.sanctorale = []
      self.configs = []
    end

    attr_accessor :today, :date_range, :formatter, :colours, :sanctorale, :locale, :configs

    def calendar
      CR::PerpetualCalendar.new(sanctorale: build_sanctorale)
    end

    def build_sanctorale
      if @sanctorale.empty?
        return DEFAULT_DATA.load
      end

      data = @sanctorale.collect do |s|
        expanded = File.expand_path s

        if s == '-'
          CR::SanctoraleLoader.new.load_from_string STDIN.read
        elsif File.file? expanded
          CR::SanctoraleLoader.new.load_from_file expanded
        elsif CR::Data[s]
          CR::Data[s].load
        else
          raise InputError.new "\"#{s}\" is neither a file, nor a valid identifier of a bundled calendar. " +
                               "Valid identifiers are: " +
                               CR::Data.each.collect(&:siglum).inspect
        end
      end

      CR::SanctoraleFactory.create_layered(*data)
    end

    def locale
      @locale || locale_in_file_metadata || DEFAULT_LOCALE
    end

    def formatter
      if @formatter == :list || (@formatter.nil? && date_range.is_a?(Day))
        Formatter::List.new highlighter(Highlighter::List), today
      elsif @formatter == :easter
        Formatter::Easter.new
      elsif @formatter == :calendars
        Formatter::Calendars.new highlighter(Highlighter::Overview), today
      elsif @formatter == :csv
        Formatter::Csv.new
      elsif @formatter == :json
        Formatter::Json.new
      else
        Formatter::Overview.new highlighter(Highlighter::Overview), today
      end
    end

    def highlighter(colourful)
      if (self.colours == false || (self.colours.nil? && !STDOUT.isatty))
        return Highlighter::No.new
      end

      colourful.new
    end

    private

    def locale_in_file_metadata
      build_sanctorale.metadata['locale']&.to_sym
    end
  end
end
