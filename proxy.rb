#!/usr/bin/env ruby
require 'sinatra'
require 'rest-client'
require 'open-uri'
require 'viddl-rb'
require 'video_info'
require 'fileutils'

set :port, 4567
set :public_folder, 'public'
set :views, 'views'

# Configurations (should be set as environment variables)
YOUTUBE_URL = "http://youtube.com"
DELETE_PASSWORD = ENV['DELETE_PASSWORD'] || "linux123"  # Replace with an env var in production
DOWNLOAD_PATH = ENV['DOWNLOAD_PATH'] || File.join(settings.public_folder, 'videos')

# Ensure download directory exists
FileUtils.mkdir_p(DOWNLOAD_PATH)

get '/' do
  send_file File.join(settings.public_folder, 'home.html')
end

get '/youtube' do
  begin
    content = URI.open(YOUTUBE_URL) { |f| f.read }
    content_type 'text/html'
    content
  rescue => e
    status 500
    "Error fetching content: #{e.message}"
  end
end

get '/error' do
  "An error has occurred: #{params[:error]}"
end

get '/clear' do
  password = params[:auth]
  return "Authentication failed." unless password == DELETE_PASSWORD

  file_count = 0
  del_count = 0
  oldest_file_date = 0.0

  Dir.glob("#{DOWNLOAD_PATH}/*.mp4") do |file|
    file_count += 1
    file_age_days = (Time.now - File.mtime(file)) / 86400.0
    oldest_file_date = [oldest_file_date, file_age_days].max

    if file_age_days >= 1.0
      File.delete(file)
      del_count += 1
    end
  end

  "#{del_count} file(s) deleted out of #{file_count} total files. Oldest file is now #{oldest_file_date.round(2)} days old."
end

get '/watch' do
  video_id = params[:v]
  return redirect to('/error?error=Video+ID+missing') unless video_id

  watch_url = "#{YOUTUBE_URL}/watch?v=#{video_id}"

  begin
    # Fetch video information
    video_info = VideoInfo.new(watch_url)
    sanitized_name = sanitize_filename(ViddlRb.get_names(watch_url)[0])

    # Define file paths
    temp_file = File.join(DOWNLOAD_PATH, "#{sanitized_name}_temp.mp4")
    final_file = File.join(DOWNLOAD_PATH, "#{sanitized_name}.mp4")

    # Download if not already present
    unless File.exist?(final_file)
      system("viddl-rb #{watch_url} --quality '*:360:mp4' --downloader aria2c --save-dir #{DOWNLOAD_PATH}")
      File.rename(temp_file, final_file) if File.exist?(temp_file)
    end

    # Render HTML using ERB template
    erb :watch, locals: { video_name: sanitized_name, video_description: video_info.description }

  rescue => e
    redirect to("/error?error=#{URI.encode(e.message)}")
  end
end

not_found do
  param = request.path + "?" + request.query_string
  begin
    RestClient.get(YOUTUBE_URL + param)
  rescue RestClient::ExceptionWithResponse => e
    status 404
    "Not Found: #{e.message}"
  end
end

helpers do
  # Helper to sanitize filenames
  def sanitize_filename(filename)
    filename.gsub(/[^\w\s-]/, '').gsub(/_/, '').strip
  end
end
