require 'optparse'
require 'pattern-match'

module Calrom
  # Parses command line options, produces Config.
  class OptionParser
    using PatternMatch

    class CustomizedOptionParser < ::OptionParser
      def separator(string)
        super "\n" + string
      end
    end

    def self.call(argv)
      self.new.call(argv)
    end

    def call(argv)
      config = Config.new

      today = config.today
      year = today.year
      month = today.month
      day = nil
      another_day = nil

      range_type = nil

      opt_parser = CustomizedOptionParser.new do |opts|
        opts.banner = <<~EOS
        Usage: calrom [options] [arg1 [arg2]]

        Specifying date range (cal/ncal-compatible):

          calrom             - current month
          calrom -m 5        - May of the current year
          calrom -m 5p       - May of the previous year
          calrom -m 5f       - May of the following year
          calrom -m 5 2000   - May 2000
          calrom 5 2000      - also May 2000
          calrom 2000        - whole year 2000
          calrom -y 2000     - also whole year 2000
          calrom -y          - whole current year

        Specifying date range (not cal-compatible):

          calrom 2000-05-31              - specified day (only)
          calrom 2000-05-31 2000-07-01   - arbitrary date range
          calrom (--yesterday|--today|--tomorrow)

        EOS

        opts.separator 'Configuration files'

        opts.on('--config=CONFIG', 'load configuration from file (may be used multiple times, all specified files will be loaded)') do |value|
          config.configs << value
        end

        opts.separator 'Options selecting date range'

        # cal
        opts.on('-m MONTH', '--month=MONTH', 'display the specified month. \'f\' or \'p\' can be appended to display the same month of the following or previous year respectively') do |value|
          range_type = :month
          if value =~ /^(\d+)([pf])$/
            month = $1
            year = validate_year(year) + ($2 == 'f' ? 1 : -1)
          else
            month = value
          end
        end

        # cal
        opts.on('-y', '--year', 'display specified (or current) year') do |value|
          range_type = :year
        end

        opts.on('--yesterday', 'display previous day') do |value|
          day = Date.today - 1
          range_type = :day
        end

        opts.on('--today', 'display current day') do |value|
          day = Date.today
          range_type = :day
        end

        opts.on('--tomorrow', 'display following day') do |value|
          day = Date.today + 1
          range_type = :day
        end

        opts.separator "Options configuring liturgical calendar"

        opts.on('-c CAL', '--calendar=CAL', 'specify (sanctorale) calendar to use. If repeated, layers all specified calendars one over another') do |value|
          config.sanctorale << value
        end

        opts.on('--[no-]load-parents', 'explicitly enable/disable parent calendar loading') do |value|
          config.load_parents = value
        end

        locales_help = I18n.available_locales.join(', ')
        opts.on('--locale=LOCALE', "override language in which temporale celebration titles are rendered (supported: #{locales_help})") do |value|
          config.locale = value.to_sym
        end

        opts.separator 'Options affecting presentation'

        opts.on('-l', '--list', 'display detailed listing of days and celebrations (synonym to --format=list)') do
          config.formatter = :list
        end

        supported_formats = %i(overview list csv json)
        formats_help = supported_formats.join(', ')
        opts.on('--format=FORMAT', supported_formats, "specify output format (supported: #{formats_help})") do |value|
          config.formatter = value
        end

        # cal
        opts.on('-e', '--easter', 'display date of Easter (only)') do
          config.formatter = :easter
        end

        opts.on('--calendars', 'list bundled calendars') do |value|
          config.formatter = :calendars
        end

        opts.on('--[no-]color', 'enable/disable colours (enabled by default)') do |value|
          config.colours = value
        end

        opts.on('-v', '--verbose', 'enable verbose output') do
          config.verbose = true
        end

        opts.separator 'Debugging options'

        # cal
        opts.on('-d YM', '--current-month=YM', 'use given month (YYYY-MM) as the current month (for debugging of date range selection)') do |value|
          year, month = value.split '-'
        end

        # cal
        opts.on('-H DATE', '--highlight-date=DATE', 'use given date as the current date (for debugging of highlighting)') do |value|
          config.today = validate_day value
        end

        opts.separator 'Information regarding calrom'

        opts.on('-V', '--version', 'display calrom version') do
          puts 'calrom v' + Calrom::VERSION
          exit
        end

        # Normally optparse defines this option by default, but once -H option is added,
        # for some reason -h (if not defined explicitly) is treated as -H.
        opts.on('-h', '--help', 'display this help') do
          puts opts
          exit
        end
      end

      arguments = opt_parser.parse argv

      iso_date_regexp = /^(\d{4}-\d{2}-\d{2})$/
      match(arguments) do
        with(_[iso_date_regexp.(date)]) do
          range_type = :day
          day = date
        end

        with(_[iso_date_regexp.(date), iso_date_regexp.(another_date)]) do
          range_type = :free
          day = date
          another_day = another_date
        end

        with(_[y]) do
          range_type ||= :year
          year = y
        end

        with(_[m, y]) do
          range_type = :month
          month, year = m, y
        end

        with([]) {}

        with(_) do
          raise InputError.new('too many arguments')
        end
      end

      config.date_range =
        build_date_range(
          range_type,
          validate_year(year),
          validate_month(month),
          day && validate_day(day),
          another_day && validate_day(another_day)
        )

      config.freeze
    end

    protected

    def validate_year(year)
      unless year.is_a?(Integer) || year =~ /^\d+$/
        raise InputError.new("not a valid year #{year}")
      end

      year.to_i
    end

    def validate_month(month)
      unless month.is_a?(Integer) ||
             (month =~ /^\d+$/ && (1..12).include?(month.to_i))
        raise InputError.new("not a valid month #{month}")
      end

      month.to_i
    end

    def validate_day(day)
      return day if day.is_a? Date

      Date.parse(day)
    rescue ArgumentError
      raise InputError.new("not a valid date #{day}")
    end

    def build_date_range(range_type, year, month, day, another_day=nil)
      range =
        case range_type
        when :year
          Year.new(year)
        when :day
          Day.new(day)
        when :free
          DateRange.new(day, another_day)
        else
          Month.new(year, month)
        end

      beginning = CR::Calendar::EFFECTIVE_FROM
      if range.first < beginning
        raise InputError.new("implemented calendar system in use only since #{beginning}")
      end

      range
    end
  end
end
