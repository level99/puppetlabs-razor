require 'fileutils'
require 'uri'
require 'pathname'
require 'digest/md5'
require Pathname.new(__FILE__).dirname.dirname.dirname.dirname.expand_path + 'puppet_x/puppet_labs/razor'

Puppet::Type.type(:rz_image).provide(:default) do

  commands :razor => 'razor'
  commands :curl  => 'curl'

  def self.query_razor
    PuppetX::PuppetLabs::Razor.new(method(:razor))
  end

  def query_razor
    self.class.query_razor
  end

  mk_resource_methods

  def self.instances
    razor_images = Array.new

    images = query_razor.get_images

    images.each do |i|
      i[:ensure] = :present
      # fallback to use the image iso name for mk.
      i[:name]   = i[:name] || i[:isoname]
      razor_images << new(i)
    end
    razor_images
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  # Clear out the cached values.
  def flush
    @property_hash.clear
  end

  def download(source, target)
    Puppet.notice("Downloading rz_image from #{source} to #{target} ...")
    FileUtils.mkdir_p(File.dirname(target))
    curl '-f', '-L', source, '-a', '-o', target
  end

  def create
    @property_hash[:ensure] = :present

    begin
      uri = URI.parse(resource[:source])
      if uri.scheme =~ /^http/
        source = File.join(resource[:cache], File.basename(uri.path))

        if !File.exist?(source) || !md5_match?(source, resource[:md5sum])
          download(resource[:source], source)
        end
      else
        source = resource[:source]
        if !File.file?(source) || !md5_match?(source, resource[:md5sum])
          download(resource[:url], source)
        end
      end

      case resource[:type]
      when :os
        Puppet.debug "razor image add -t #{resource[:type]} -p #{resource[:source]} -n #{resource[:name]} -v #{resource[:version]}"
        razor 'image', 'add', '-t', resource[:type], '-p', source, '-n', resource[:name], '-v', resource[:version]
      else
        Puppet.debug "razor image add -t #{resource[:type]} -p #{resource[:source]}"
        razor 'image', 'add', '-t', resource[:type], '-p', source
      end
    ensure
      FileUtils.remove_entry_secure(tmpdir) if tmpdir
    end
  end

  def destroy
    @property_hash[:ensure] = :absent
    razor 'image', 'remove', @property_hash[:uuid]
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  # Match a given md5 with the file in source.
  #
  # Returns true if the md5 is not set.
  # Returns true if the md5 given matches with the file's md5.
  def md5_match?(file, md5)
    md5.nil? || Digest::MD5.file(source).hexdigest == md5
  end
end
