#!/usr/bin/ruby

require 'sinatra'
require 'sinatra-websocket'

IO.write("/var/local/http-keystore.pid", Process.pid)

set :server, 'thin'
set :sockets, []
set :port, 11000
set :bind, "0.0.0.0"

def keys_dir
  "keys"
end

def path_for_key(key)
  "#{keys_dir}/#{key}"
end

def send_key(key, ws)
  path = path_for_key(key)
  if File.exist?(path) then
    ws.send({"Last-Modified" => File.mtime(path).to_s, "data" => File.read(path)}.to_json)
  else
    ws.send({"Last-Modified" => nil, "data" => nil}.to_json)
  end
end

get '/:key' do |key|
  halt 400 if key.include?("/") || key.start_with?(".")
  path = path_for_key(key)

  if request.websocket? then
    request.websocket do |ws|
      ws.onopen do
        send_key(key, ws)
        settings.sockets << ws
      end

      ws.onmessage do |msg|
        send_key(key, ws)
      end

      ws.onclose do
        settings.sockets.delete(ws)
      end
    end
  else
    halt 404 unless File.exist?(path)
    [ 200, { "Last-Modified" => File.mtime(path).to_s }, File.read(path) ]
  end
end

post '/:key' do |key|
  halt 400 if key.include?("/") || key.start_with?(".")

  request.body.rewind
  Dir.mkdir(keys_dir) unless File.exist?(keys_dir)
  IO.write(path_for_key(key), request.body.read)
  [ 200, {}, "" ]
end

delete '/:key' do |key|
  halt 400 if key.include?("/") || key.start_with?(".")
  halt 404 unless File.exist?(path_for_key(key))

  File.unlink(path_for_key(key))
end

