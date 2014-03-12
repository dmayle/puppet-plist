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
      begin
        plistbuddy.options['uid'] = @resource.user
        file_path = @resource.filename
        keys = @resource.keys
        value_type = @resource.value_type

        if value_type == :array

          # Add the array entry if necessary
          if !keypresent?
            buddycmd = "Add %s %s" % [keys.join(':').inspect, value_type]
            plistbuddy(file_path, '-c', buddycmd)
          end

          # Add the elements. We have to do this starting from zero, because we can't add an element with a gap
          @resource[:value].each_with_index do |value, index|
            keys = @resource.keys + [index]
            if !keypresent? keys
              buddycmd = "Add %s %s" % [keys.join(':').inspect, inferred_type(value)]
              plistbuddy(file_path, '-c', buddycmd)
            end
            buddycmd = "Set %s %s" % [keys.join(':').inspect, value.inspect]
            plistbuddy(file_path, '-c', buddycmd)
          end
          reload_cache('read', file_path)
        elsif value_type == :date # Example of a date that PlistBuddy will accept Mon Jan 01 00:00:00 EST 4001
          native_date = Date.parse(@resource[:value])
          # Note that PlistBuddy will only accept certain timezone formats like 'EST' or 'GMT' but not other valid
          # timezones like 'PST'. So the compromise is that times must be in UTC
          buddycmd = keypresent? ? "Set %s %s" % [keys.join(':').inspect, native_date.strftime('%a %b %d %H:%M:%S %Y')]
                                 : "Add %s %s %s" % [keys.join(':').inspect, value_type,  native_date.strftime('%a %b %d %H:%M:%S %Y')]
        else
          buddycmd = keypresent? ? "Set %s %s" % [keys.join(':').inspect, @resource[:value].inspect]
                                 : "Add %s %s %s" % [keys.join(':').inspect, value_type, @resource[:value].inspect]
        end

        plistbuddy(file_path, '-c', buddycmd)
        reload_cache('read', file_path)

      rescue Exception
        false
      end
  end

  def destroy
    begin
      plistbuddy.options['uid'] = @resource.user
      file_path = @resource.filename
      keys = @resource.keys

      buddycmd = "Delete %s" % keys.join(':').inspect
      plistbuddy(file_path, '-c', buddycmd)
      reload_cache('read', file_path)
    rescue Exception
      false
    end
  end

  def keypresent?(keys = nil)

    begin
      file_path = @resource.filename
      keys ||= @resource.keys

      buddycmd = "Print %s" % keys.join(':').inspect
      plistbuddy(file_path, '-c', buddycmd).strip

      true

    rescue Exception
      # A bad return value from plistbuddy indicates that the key does not exist.
      false
    end
  end

  def exists?

    begin
      plistbuddy.options['uid'] = @resource.user
      file_path = @resource.filename
      keys = @resource.keys

      # Exception handles key not present
      notify 'Checking for key'
      buddycmd = "Print %s" % keys.join(':').inspect
      buddyvalue = plistbuddy(file_path, '-c', buddycmd).strip

      # TODO: Compare the elements of the array by parsing the output from PlistBuddy
      # TODO: Convert desired dates into a format that can be compared by value.
      # TODO: Find a way of comparing Real numbers by casting to Float etc.
      case @resource.value_type
        when :array
          notify 'Is array type'
          @resource[:value].each_with_index do |value, index|
            notify 'Checking index %s' % index
            keys = @resource.keys + [index]
            if !keypresent? keys
              return false
            end
            buddycmd = "Print %s" % keys.join(':').inspect
            buddyvalue = plistbuddy(file_path, '-c', buddycmd).strip
            notify 'Comparing values %s and %s' % [buddyvalue.inspect, value.to_s.inspect]
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
