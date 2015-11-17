module Supply
  class Setup
    def perform_download
      if File.exist?(metadata_path)
        Helper.log.info "Metadata already exists at path '#{metadata_path}'".yellow
        return
      end

      client.begin_edit(package_name: Supply.config[:package_name])

      client.listings.each do |listing|
        store_metadata(listing)
        create_screenshots_folder(listing)
        download_images(listing)
      end

      client.abort_current_edit

      Helper.log.info "Successfully stored metadata in '#{metadata_path}'".green
    end

    def store_metadata(listing)
      containing = File.join(metadata_path, listing.language)
      FileUtils.mkdir_p(containing)

      Supply::AVAILABLE_METADATA_FIELDS.each do |key|
        path = File.join(containing, "#{key}.txt")
        Helper.log.info "Writing to #{path}..."
        File.write(path, listing.send(key))
      end
    end

    def download_images(listing)
      # We cannot download existing screenshots as they are compressed
      # But we can at least download the images
      require 'net/http'

      IMAGES_TYPES.each do |image_type|
        next if ['featureGraphic'].include?(image_type) # we don't get all files in full resolution :(

        begin
          Helper.log.info "Downloading #{image_type} for #{listing.language}..."

          url = client.fetch_images(image_type: image_type, language: listing.language).last
          next unless url

          path = File.join(metadata_path, listing.language, IMAGES_FOLDER_NAME, "#{image_type}.png")
          File.write(path, Net::HTTP.get(URI.parse(url)))
        rescue => ex
          Helper.log.error ex.to_s
          Helper.log.error "Error downloading '#{image_type}' for #{listing.language}...".red
        end
      end
    end

    def create_screenshots_folder(listing)
      containing = File.join(metadata_path, listing.language)

      FileUtils.mkdir_p(File.join(containing, IMAGES_FOLDER_NAME))
      Supply::SCREENSHOT_TYPES.each do |screenshot_type|
        FileUtils.mkdir_p(File.join(containing, IMAGES_FOLDER_NAME, screenshot_type))
      end

      Helper.log.info "Due to the limit of the Google Play API `supply` can't download your existing screenshots..."
    end

    private

    def metadata_path
      @metadata_path ||= Supply.config[:metadata_path]
      @metadata_path ||= "fastlane/metadata/android" if Helper.fastlane_enabled?
      @metadata_path ||= "metadata" unless Helper.fastlane_enabled?

      return @metadata_path
    end

    def client
      @client ||= Client.new(path_to_key: Supply.config[:key],
                                  issuer: Supply.config[:issuer],
                              passphrase: Supply.config[:passphrase])
    end
  end
end
