require 'socket'
require_relative 'request_parser'

class RactorServer
  PORT = ENV.fetch('PORT', 3000)
  BIND = ENV.fetch('BIND', '127.0.0.1').freeze
  SOCKET_READ_BACKLOG = ENV.fetch('TCP_BACKLOG', 12).to_i
  WORKERS_COUNT = ENV.fetch('WORKERS', 4).to_i

  attr_accessor :app

  # app: Rack app
  def initialize(app)
    self.app = app
  end

  def start
    # the dispatcher is going to be used to
    # fairly dispatch incoming requests,
    # we pass the queue into workers
    # and the first free worker gets
    # the yielded request
    dispatcher = Ractor.new do
      loop do
        conn = Ractor.recv
        Ractor.yield(conn, move: true)
      end
    end

    # workers determine concurrency
    WORKERS_COUNT.times.map do
      # we need to pass the dispatcher and the server so they are available
      # inside Ractor
      Ractor.new(dispatcher, self) do |dispatcher, server|
        loop do
          # this method blocks until the dispatcher yields a connection
          conn = dispatcher.take
          request = RequestParser.new(conn).parse
          # in a real app there would be a whole lot more information
          # about the request, but we are gonna keep it simple
          status, headers, body = server.app.call(
             'REQUEST_METHOD' => request.method,
             'PATH_INFO' => request.path,
             'QUERY_STRING' => request.query
           )
          server.respond(conn, status, headers, body)
        ensure
          conn&.close
        end
      end
    end

    # the listener is going to accept new connections
    # and pass them onto the dispatcher,
    # we make it a separate Ractor so it responds quicker
    listener = Ractor.new(dispatcher) do |queue|
      socket = Socket.new(:INET, :STREAM)
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      socket.bind(Addrinfo.tcp(BIND, PORT))
      socket.listen(SOCKET_READ_BACKLOG)
      loop do
        conn, _addr_info = socket.accept
        queue.send(conn, move: true)
      end
    end

    Ractor.select(listener)
  end

  def respond(conn_sock, status, headers, body)
    status_text = {
      200 => 'OK',
      404 => 'Not Found'
    }[status]
    conn_sock.send("HTTP/1.1 #{status} #{status_text}\r\n", 0)
    conn_sock.send("Content-Length: #{body.sum(&:length)}\r\n", 0)
    headers.each_pair do |name, value|
      conn_sock.send("#{name}: #{value}\r\n", 0)
    end
    conn_sock.send("Connection: close\r\n", 0)
    conn_sock.send("\r\n", 0)
    body.each do |chunk|
      conn_sock.send(chunk, 0)
    end
  end
end
