require 'puppet/util/suidmanager'

Puppet::Type.type(:plist).provide :plistbuddy, :parent => Puppet::Provider do

  desc "This provider alters plist values using the PlistBuddy(8) command line utility.

  Because of the way that PlistBuddy deals with types, it cannot convert an existing Plist key from one type to another.
  The key must first be removed in order to change the type of value it contains.

  There also seems to be no documentation about the appropriate date format.
  "

  commands :plistbuddy => "/usr/libexec/PlistBuddy"
  # On Mavericks, editing plist files directly bypasses the cache, so we force a reload after changes are made.
  commands :reload_cache => "defaults"
  confine :operatingsystem => :darwin

  def create
    self.info "Starting create"
      begin
        file_path = @resource.filename
        keys = @resource.keys
        value_type = @resource.value_type

        if value_type == :array

          # Add the array entry if necessary
          self.info 'Array keypresent'
          unless keypresent?
            self.info 'Creating key'
            buddycmd = "Add %s %s" % [keys.join(':').inspect, value_type]
            Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
              plistbuddy(file_path, '-c', buddycmd)
            end
          end

          # Add the elements. We have to do this starting from zero, because we can't add an element with a gap
          @resource[:value].each_with_index do |value, index|
            keys = @resource.keys + [index]
            unless keypresent? keys
              buddycmd = "Add %s %s" % [keys.join(':').inspect, inferred_type(value)]
              Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
                plistbuddy(file_path, '-c', buddycmd)
              end
            end
            buddycmd = "Set %s %s" % [keys.join(':').inspect, value.inspect]
            Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
              plistbuddy(file_path, '-c', buddycmd)
            end
          end
          Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
            reload_cache('read', file_path)
          end
        elsif value_type == :date # Example of a date that PlistBuddy will accept Mon Jan 01 00:00:00 EST 4001
          self.info 'Date type'
          native_date = Date.parse(@resource[:value])
          # Note that PlistBuddy will only accept certain timezone formats like 'EST' or 'GMT' but not other valid
          # timezones like 'PST'. So the compromise is that times must be in UTC
          buddycmd = keypresent? ? "Set %s %s" % [keys.join(':').inspect, native_date.strftime('%a %b %d %H:%M:%S %Y')]
                                 : "Add %s %s %s" % [keys.join(':').inspect, value_type,  native_date.strftime('%a %b %d %H:%M:%S %Y')]
        else
          self.info 'Generic type'
          buddycmd = keypresent? ? "Set %s %s" % [keys.join(':').inspect, @resource[:value].inspect]
                                 : "Add %s %s %s" % [keys.join(':').inspect, value_type, @resource[:value].inspect]
        end

        Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
          plistbuddy(file_path, '-c', buddycmd)
          reload_cache('read', file_path)
        end

      rescue Exception
        false
      end
  end

  def destroy
    self.info "Starting destroy"
    begin
      file_path = @resource.filename
      keys = @resource.keys

      buddycmd = "Delete %s" % keys.join(':').inspect
      Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
        plistbuddy(file_path, '-c', buddycmd)
        reload_cache('read', file_path)
      end
    rescue Exception
      false
    end
  end

  def keypresent?(keys = nil)
    self.info "Starting keypresent"

    begin
      file_path = @resource.filename
      keys ||= @resource.keys

      buddycmd = "Print %s" % keys.join(':').inspect
      Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
        self.info 'Keypresent check %s' % buddycmd
        plistbuddy(file_path, '-c', buddycmd).strip
      end

      true

    rescue Exception => for_traceback
      self.info 'Keypresent exception'
      self.info for_traceback
      self.info for_traceback.backtrace
      # A bad return value from plistbuddy indicates that the key does not exist.
      false
    end
  end

  def exists?
    self.info "Starting exists"

    begin
      file_path = @resource.filename
      keys = @resource.keys

      # Exception handles key not present
      self.info 'Checking for key'
      buddycmd = "Print %s" % keys.join(':').inspect
      buddyvalue = nil
      Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
        buddyvalue = plistbuddy(file_path, '-c', buddycmd).strip
      end

      # TODO: Compare the elements of the array by parsing the output from PlistBuddy
      # TODO: Convert desired dates into a format that can be compared by value.
      # TODO: Find a way of comparing Real numbers by casting to Float etc.
      case @resource.value_type
        when :array
          self.info 'Is array type'
          max_index = 0
          @resource[:value].each_with_index do |value, index|
            self.info 'Checking index %s' % index
            keys = @resource.keys + [index]
            unless keypresent? keys
              return false
            end
            if index > max_index
              max_index = index
            end
            buddycmd = "Print %s" % keys.join(':').inspect
            Puppet::Util::SUIDManager.asuser(@resource[:user], @resource[:group]) do
              buddyvalue = plistbuddy(file_path, '-c', buddycmd).strip
            end
            self.info 'Comparing values %s and %s' % [buddyvalue.inspect, value.to_s.inspect]
            if buddyvalue != value.to_s
              return false
            end
          end
          true # Assume the existence of the array even if the elements are different. Otherwise we need to parse the output
        when :real
          true # Assume the existence of the real number because the actual value will be stored differently.
        when :date
          true # Assume the existence of the date is enough. This is because the timezone will be converted upon adding the date.
        else
          @resource[:value].to_s == buddyvalue
      end

    rescue Exception
      # A bad return value from plistbuddy indicates that the key does not exist.
      false
    end
  end

  def inferred_type(value)
    case value
    when Array then :array
    when Hash then :dict
    when %r{^\d+$} then :integer
    when %r{^\d*\.\d+$} then :real # Doesnt really catch all valid real numbers.
    when true || false then :bool
    when %r{^\d{4}-\d{2}-\d{2}} then :date # Not currently supported, requires munging to native Date type
    else :string
    end
  end
end
