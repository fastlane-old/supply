module Supply
  class Uploader
    def perform_upload
      FastlaneCore::PrintTable.print_values(config: Supply.config, hide_keys: [:issuer], title: "Summary for supply #{Supply::VERSION}")

      client.begin_edit(package_name: Supply.config[:package_name])

      raise "No local metadata found, make sure to run `supply init` to setup supply".red unless metadata_path || Supply.config[:apk]

      if metadata_path
        raise "Could not find folder".red unless File.directory? metadata_path

        Dir.foreach(metadata_path) do |language|
          next if language.start_with?('.') # e.g. . or .. or hidden folders

          listing = client.listing_for_language(language)

          upload_metadata(language, listing) unless Supply.config[:skip_upload_metadata]
          upload_images(language) unless Supply.config[:skip_upload_images]
          upload_screenshots(language) unless Supply.config[:skip_upload_screenshots]
          upload_changelogs(language) unless Supply.config[:skip_upload_metadata]
        end
      end

      upload_binary unless Supply.config[:skip_upload_apk]

      promote_track

      Helper.log.info "Uploading all changes to Google Play..."
      client.commit_current_edit!
      Helper.log.info "Successfully finished the upload to Google Play".green
    end

    def promote_track
      if Supply.config[:track_promote_to]
        version_codes = client.track_version_codes(Supply.config[:track])
        for apk_version_code in version_codes
          client.update_track(Supply.config[:track], 1.0, nil)
          client.update_track(Supply.config[:track_promote_to], 1.0, apk_version_code)
        end
      end
    end

    def upload_changelogs(language)
      client.apks_version_codes.each do |apk_version_code|
        upload_changelog(language, apk_version_code)
      end
    end

    def upload_changelog(language, apk_version_code)
      path = File.join(metadata_path, language, Supply::CHANGELOGS_FOLDER_NAME, "#{apk_version_code}.txt")
      if File.exist?(path)
        Helper.log.info "Updating changelog for code version '#{apk_version_code}' and language '#{language}'..."
        apk_listing = ApkListing.new(File.read(path), language, apk_version_code)
        client.update_apk_listing_for_language(apk_listing)
      end
    end

    def upload_metadata(language, listing)
      Helper.log.info "Loading metadata for language '#{language}'..."

      Supply::AVAILABLE_METADATA_FIELDS.each do |key|
        path = File.join(metadata_path, language, "#{key}.txt")
        listing.send("#{key}=".to_sym, File.read(path)) if File.exist?(path)
      end
      listing.save
    end

    def upload_images(language)
      Supply::IMAGES_TYPES.each do |image_type|
        search = File.join(metadata_path, language, Supply::IMAGES_FOLDER_NAME, image_type) + ".#{IMAGE_FILE_EXTENSIONS}"
        path = Dir.glob(search, File::FNM_CASEFOLD).last
        next unless path

        Helper.log.info "Uploading image file #{path}..."
        client.upload_image(image_path: File.expand_path(path),
                            image_type: image_type,
                              language: language)
      end
    end

    def upload_screenshots(language)
      Supply::SCREENSHOT_TYPES.each do |screenshot_type|
        search = File.join(metadata_path, language, Supply::IMAGES_FOLDER_NAME, screenshot_type, "*.#{IMAGE_FILE_EXTENSIONS}")
        paths = Dir.glob(search, File::FNM_CASEFOLD)
        next unless paths.count > 0

        client.clear_screenshots(image_type: screenshot_type, language: language)

        paths.sort.each do |path|
          Helper.log.info "Uploading screenshot #{path}..."
          client.upload_image(image_path: File.expand_path(path),
                              image_type: screenshot_type,
                                language: language)
        end
      end
    end

    def upload_binary
      if Supply.config[:apk]
        Helper.log.info "Preparing apk at path '#{Supply.config[:apk]}' for upload..."
        apk_version_code = client.upload_apk(Supply.config[:apk])

        Helper.log.info "Updating track '#{Supply.config[:track]}'..."
        if Supply.config[:track].eql? "rollout"
          client.update_track(Supply.config[:track], Supply.config[:rollout], apk_version_code)
        else
          client.update_track(Supply.config[:track], 1.0, apk_version_code)
        end

        if metadata_path
          Dir.foreach(metadata_path) do |language|
            next if language.start_with?('.') # e.g. . or .. or hidden folders
            upload_changelog(language, apk_version_code)
          end
        end

      else
        Helper.log.info "No apk file found, you can pass the path to your apk using the `apk` option"
      end
    end

    private

    def client
      @client ||= Client.new(path_to_key: Supply.config[:key],
                                   issuer: Supply.config[:issuer])
    end

    def metadata_path
      Supply.config[:metadata_path]
    end
  end
end
