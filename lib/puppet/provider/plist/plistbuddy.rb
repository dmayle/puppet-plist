Puppet::Type.type(:plist).provide :plistbuddy, :parent => Puppet::Provider do

  desc "This provider alters plist values using the PlistBuddy(8) command line utility.

  Because of the way that PlistBuddy deals with types, it cannot convert an existing Plist key from one type to another.
  The key must first be removed in order to change the type of value it contains.

  There also seems to be no documentation about the appropriate date format.
  "

  commands :plistbuddy => "/usr/libexec/PlistBuddy"
  confine :operatingsystem => :darwin

  def create
      begin
        file_path = @resource.filename
        keys = @resource.keys
        value_type = @resource.value_type

        if value_type == :array

          # Add the array entry
          buddycmd = keypresent? ? "Set %s %s" % [ keys.join(':').inspect, @resource[:value].inspect ]
                                 : "Add %s %s %s" % [ keys.join(':').inspect, value_type, @resource[:value].inspect ]

          # Add the elements
          @resource[:value].each do |value|
            plistbuddy(file_path, '-c', buddycmd)
            buddycmd = keypresent? ? "Set %s:0 %s" % [ keys.join(':').inspect, value.inspect ]
                                   : "Add %s:0 %s %s" % [ keys.join(':').inspect, 'string', value.inspect ]
          end
        elsif value_type == :date # Example of a date that PlistBuddy will accept Mon Jan 01 00:00:00 EST 4001
          native_date = Date.parse(@resource[:value])
          # Note that PlistBuddy will only accept certain timezone formats like 'EST' or 'GMT' but not other valid
          # timezones like 'PST'. So the compromise is that times must be in UTC
          buddycmd = keypresent? ? "Set %s %s" % [ keys.join(':').inspect, native_date.strftime('%a %b %d %H:%M:%S %Y')]
                                 : "Add %s %s %s" % [ keys.join(':').inspect, value_type,  native_date.strftime('%a %b %d %H:%M:%S %Y')]
        else
          buddycmd = keypresent? ? "Set %s %s" % [ keys.join(':').inspect, @resource[:value].inspect ]
                                 : "Add %s %s %s" % [ keys.join(':').inspect, value_type, @resource[:value].inspect ]
        end

        plistbuddy(file_path, '-c', buddycmd)

      rescue Exception
        false
      end
  end

  def destroy
    begin
      file_path = @resource.filename
      keys = @resource.keys

      buddycmd = "Delete %s" % keys.join(':').inspect
      plistbuddy(file_path, '-c', buddycmd)
    rescue Exception
      false
    end
  end

  def keypresent?

    begin
      file_path = @resource.filename
      keys = @resource.keys

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
      file_path = @resource.filename
      keys = @resource.keys

      buddycmd = "Print %s" % keys.join(':').inspect
      buddyvalue = plistbuddy(file_path, '-c', buddycmd).strip

      # TODO: Compare the elements of the array by parsing the output from PlistBuddy
      # TODO: Convert desired dates into a format that can be compared by value.
      # TODO: Find a way of comparing Real numbers by casting to Float etc.
      case @resource.value_type
        when :array
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
end
