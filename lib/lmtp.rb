# -*- coding: utf-8 -*-
# Copyright © 2015 Marvin Gülker
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require "socket"

# LMTP server class. Instances of this class utilize a UNIX socket to implement
# the LMTP protocol (see {RFC 2033}[https://tools.ietf.org/html/rfc1854]) in its
# most minimal and basic form. LMTP is spoken by possibly any MTA, so using this
# class you can make your Ruby program an email endpoint as long as you know how
# to configure your MTA. I’ve only tested with Postfix, though, so no guarantees.
#
# Instances of this class support several callbacks. The main callback is the message
# callback, which is passed the the block to ::new. It gets called whenever the
# LMTP client hands in an email, and receives the entire email as plain text
# as its argument. You can use the “mail” library or other means to parse it.
# Other callbacks you might find useful can be set with the #logging and #headers
# methods.
#
# This class makes no use of threads for multiple connections. Thus,
# any emails submitted at once to the UNIX domain socket are processed
# ony-by-one. A single client could block all other clients thus, but
# because LMTP should only ever be used in a completely trusted
# environment (see RFC 2033, sections 3 and 5), this is not an issue.
#
# It _does_ employ a mutex for the #stop method and the checking of the
# stopping variable. This means you can safely call #stop from another
# thread.
#
# Example use:
#
#     server = LmtpServer.new("/var/spool/postfix/private/mysocket") do |message|
#       puts "--- Start of email ---"
#       puts message
#       puts "--- End of email ---"
#     end
#
#     server.logging do |level, msg|
#       $stderr.puts "[#{level}] #{msg}"
#     end
#
#     server.start
#
# The LMTP server by this class implements the following SMTP Service
# Extensions (see below for the list of RFCs). Do not implement them
# yourself by utilising #moreextensions and the callbacks, they’re
# there already!
#
# * PIPELINING
# * ENHANCEDSTATUSCODES
# * 8BITMIME
#
# RFCs implemented by this class:
#
# * {RFC 2033}[https://tools.ietf.org/html/rfc2033]
# * {RFC 2034}[https://tools.ietf.org/html/rfc2034]
# * {RFC 1854}[https://tools.ietf.org/html/rfc1854]
# * {RFC 1869}[https://tools.ietf.org/html/rfc1869]
# * {RFC 1652}[https://tools.ietf.org/html/rfc1652]
# * {RFC 821}[https://tools.ietf.org/html/rfc821] for the minimally required parts
class LmtpServer

  # The machine’s hostname is read from this file.
  HOSTNAME_FILE = "/etc/hostname"

  # Timeout in seconds when a client is forcibly disconnected when
  # it does nothing.
  attr_accessor :timeout

  # This is an array of extra extensions that are announced to
  # the client in response to LHLO. Just append the names of
  # the extensions to this array (e.g. "MYCOOLEXTENSION").
  # The class will take care to prefix is with the proper LMTP
  # reply code.
  #
  # This array is empty by default. Modifying it only makes sense
  # if you actually implement the extensions you advertise here.
  attr_accessor :moreextensions

  # Message text to return on a successful message acceptance. This is
  # automatically prefixed by "250 2.6.0 " so you don’t have to care
  # about the LMTP status code. This text is purely informational and
  # has no meaning to the protocol. It will show up in the sending
  # MTA’s logs.
  attr_accessor :successmsg

  # Create a new LMTP server.
  #
  # === Parameters
  # [path]
  #   Path on which the UNIX domain socket is created.
  #   All parent directories must exist, but the “file” itself
  #   must not exist (an ArgumentError is thrown if it exists).
  # [mode (nil)]
  #   UNIX permissions to set on the UNIX socket file as
  #   a numeric mode (example: 0666 for rw-rw-rw-).
  #   User and Group of the file are determined by whatever
  #   the process environment mandates. +nil+ means to use
  #   whatever the process umask mandates.
  # [callback]
  #   Message callback. Receives any email as a string that is
  #   passed to this LMTP server. The string will contain the
  #   original carriagereturn+newline line breaks from the protcol.
  #
  # === Return value
  # Returns the new instance.
  def initialize(path, mode = nil, &callback)
    @path     = path
    @mode     = mode
    @hostname = File.read(HOSTNAME_FILE).strip
    @msgcb    = callback
    @client   = nil
    @timeout  = 30
    @mutex    = Mutex.new
    @do_stop  = false
    @headercb = method(:default_headercb)
    @moreextensions = []
    @successmsg     = "All your bytes are belong to us."

    if File.exist?(path)
      raise(ArgumentError, "File already exists: #{path}")
    end
  end

  # Specify the logging callback. It will receive a syslog
  # logging level as a symbol and the log message.
  #
  # By default, no logging callback is set and hence nothing
  # is logged.
  def logging(&callback)
    @logcb = callback
  end

  # Override the callback used for responding to the LMTP client for
  # the LMTP commands before DATA, e.g. MAIL FROM and RCPT TO. The
  # callback receives the entire line the client sent, including the
  # trailing carriagereturn-newline.
  #
  # The default callback only answers "250 2.1.0 ok" for every
  # command.  Note that RFC 2033 (LMTP) requires in section 5 that any
  # LMTP server MUST implement RFC 2034, which in turn refers to RFC
  # 1893 for the actual status codes, so for any replies you make you
  # must make use of the extended statuscodes defined in RFC 1893 in
  # the format defined by RFC 2034. Don’t worry — both of these RFCs
  # are simple enough to just read quickly through them.
  #
  # Example:
  #
  #   server.headers do |line|
  #     case line
  #     when /^MAIL FROM/ then "250 ok"
  #     when /^RCPT TO:<.*?>/ then
  #       if this_account_exists($1)
  #         "250 2.1.5 Recipient ok"
  #       else
  #         "550 5.1.1 Recipient does not exist over here."
  #       end
  #     else
  #       "250 2.1.0 ok"
  #     end
  #   end
  #
  # Note that the replies you define here are not immediately sent
  # to the client, which is a result of the PIPELINING extension
  # that is required by LMTP (see RFC 2033, section 5, and RFC 1854).
  # Instead they’re accumulated and send as a big swall to the client
  # when he issues the DATA command.
  def headers(&callback)
    @headercb = callback
  end

  # Halt the running server. This method is threadsafe.
  def stop
    @mutex.synchronize{ @do_stop = true }
  end

  # Create the UNIX domain socket and start listening on it.
  # This method starts a listening loop and thus blocks.
  # Use #stop from another thread to issue a halt.
  def start
    log :info, "Starting server"
    @mutex.synchronize{ @do_stop = false }

    UNIXServer.open(@path) do |server|
      File.chmod(@mode, @path) if @mode

      log :info, "Accepting connections."
      while @client = server.accept
        addr = @client.addr.last
        log :info, "Client connect from #{addr}."

        # TODO: Use #accept_nonblock in loop? This way, a client has to connect
        # first to have the server shut down.
        break if @mutex.synchronize{ @do_stop }

        begin
          catch :timeout do
            handle_client
          end
        rescue => e
          log :err, "Exception: #{e.class.name}: #{e.message}: #{e.backtrace.join("\n")}"
          log :err, "Aborting connection due to exception."
          @client.close
        end

        log :info, "Client connection closed: #{addr}"
        @client = nil
      end

    end

    log :info, "Server stopped."
  ensure
    if File.exist?(@path)
      log :info, "Removing UNIX socket '#@path'"
      File.delete(@path)
    end
  end

  private

  def log(level, msg)
    @logcb.call(level, msg) if @logcb
  end

  def reply(msg)
    str = msg.strip + "\r\n"
    log :debug, "server: #{str.inspect}"
    @client.puts(str)
  end

  def gets(raw = false)
    if IO.select([@client], nil, nil, @timeout)
      str = @client.gets
      log :debug, "client: #{str.inspect}"
      return nil if str.nil?

      str.gsub!("\r\n", "\n") unless raw

      if str.strip == "RSET" && !raw # Ensure that in DATA we can ignore it if this text occurs
        reply "220 2.0.0 Resetting."
        throw :rset
      end

      str
    else
      log :err, "Client #{@client.addr.last} timed out. Closing."
      reply "422 4.5.0 Timeout."
      @client.close
      throw :timeout
    end
  end

  def handle_client
    reply "220 #{@hostname} LMTP server ready"

    line = gets
    if line !~ /^LHLO (.*?)$/
      reply "500 5.5.1 You must great me first."
      @client.close
      return
    end

    log :info, "Client reports name: '#$1'"

    reply "250-#{@hostname}"
    reply "250-PIPELINING"
    reply "250-ENHANCEDSTATUSCODES"
    @moreextensions.each{|ext| reply("250-#{ext}")}
    reply "250 8BITMIME"

    loop do
      no_valid_recipients = true

      catch :rset do
        # Allow pipelining by accumulation
        responses = []
        loop do
          line = gets
          break if line =~ /^DATA$/
          response = @headercb.call(line)

          # Conform to section 4.2(2) of RFC 2033. We need at least one RCPT
          # command to succeed, otherwise DATA further below must fail.
          if line.start_with?("RCPT") && response.start_with?("2")
            no_valid_recipients = false
          end

          responses << response
        end

        # Answer the pipeline
        responses.each do |response|
          reply response
        end

        # Prepare for receiving
        reply "354 Start data. End with <CRLF>.<CRLF>"
        message = ""
        loop do
          line = gets(true) # Keep carriage returns and prevent RSET
          break if line.strip == "."

          # Honour transparency process as per section 4.5.2 of RFC 821
          line.slice!(0) if line.start_with?(".") && line.strip.length > 1

          message << line
        end

        # Conform to section 4.2(2) of RFC 2033 by failing with 503 if no valid
        # recipients were found.
        if no_valid_recipients
          log :info, "No valid RCPT commands received, denying relay."
          reply "503 5.0.0 No valid RCPT command received, denying DATA."
          next
        end

        begin
          log :debug, "Invoking message callback."
          @msgcb.call(message)
        rescue => e
          reply "551 Internal error: #{e.class}: #{e.message}"
          @client.close
          return
        end

        reply "250 2.6.0 #@successmsg"

        final = gets
        if final
          if final =~ /^QUIT$/
            # Regular QUIT

            reply "221 2.0.0 #{@hostname} Goodbye."
            @client.close
            return
          else
            # Not closing connection, client wants to sent another email
          end
        else
          # Whoops. Client closed connection without QUIT. Bad guy!
          log :warning, "Client closed connection without QUIT."
          @client.close
          return
        end
      end
    end
  end

  def default_headercb(line)
    "250 2.1.0 ok"
  end

end
