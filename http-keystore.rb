#!/usr/bin/env ruby

require 'sinatra'
require 'sinatra-websocket'

IO.write("/tmp/http-keystore-builtin.pid", Process.pid)

set :server, 'thin'
set :sockets, []
set :port, 11000
set :bind, "0.0.0.0"

$sockets_by_key = {}

def keys_dir
  "keys"
end

def path_for_key(key)
  "#{keys_dir}/#{key}"
end

def register_socket(key, ws)
  $sockets_by_key[key] ||= []
  $sockets_by_key[key] << ws
end

def unregister_socket(key, ws)
  $sockets_by_key[key].delete(ws)
end

def send_key_to_socket(key, ws)
  path = path_for_key(key)
  if File.exist?(path) then
    ws.send({"Last-Modified" => File.mtime(path).to_s, "data" => File.read(path)}.to_json)
  else
    ws.send({"Last-Modified" => nil, "data" => nil}.to_json)
  end
end

def send_key(key)
  ($sockets_by_key[key] || []).each { |ws| send_key_to_socket(key, ws) }
end

get '/:key' do |key|
  halt 400 if key.include?("/") || key.start_with?(".")
  path = path_for_key(key)

  if request.websocket? then
    request.websocket do |ws|
      ws.onopen do
        register_socket(key, ws)
        send_key_to_socket(key, ws)
        settings.sockets << ws
      end

      ws.onmessage do |msg|
        send_key_to_socket(key, ws)
      end

      ws.onclose do
        unregister_socket(key, ws)
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

  send_key(key)

  [ 200, {}, "" ]
end

delete '/:key' do |key|
  halt 400 if key.include?("/") || key.start_with?(".")
  halt 404 unless File.exist?(path_for_key(key))

  File.unlink(path_for_key(key))
  send_key(key)
end

