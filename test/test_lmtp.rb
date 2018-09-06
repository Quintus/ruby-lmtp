# coding: utf-8
require "minitest/autorun"
require_relative "../lib/lmtp"

Thread.abort_on_exception = true

class TestLmtp < Minitest::Test

  SOCKET_PATH = "/tmp/test-lmtp.sock"
  TEMPMAIL_PATH = "/tmp/test-lmtp-mail.txt"

  def setup
    @serverthread = Thread.new do
      File.open(File.join(File.expand_path(File.dirname(__FILE__)), "output.txt"), "a") do |outfile|
        outfile.puts "<><><><><><><><><><>"
        server = LmtpServer.new(SOCKET_PATH) do |msg|
          File.open(TEMPMAIL_PATH, "wb"){|f| f.write(msg)}

          outfile.puts("--- Received email ---")
          outfile.puts(msg)
          outfile.puts("--- End of email ---")
        end

        server.logging do |level, msg|
          outfile.puts("[#{level}] #{msg}")
        end

        server.start
      end
    end
    sleep 1

    @socket = UNIXSocket.new(SOCKET_PATH)
  end

  def teardown
    @serverthread.terminate
    @serverthread.join
    File.delete(SOCKET_PATH) if File.exist?(SOCKET_PATH)
    File.delete(TEMPMAIL_PATH) if File.exist?(TEMPMAIL_PATH)
  end

  def test_normal
    assert_match /^220 /, read

    request "LHLO localhost"
    ary = read.split("\n")

    ary[0..-2].each{|item| assert_match /^250-/, item }
    assert_match /^250 /, ary[-1]

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request email
    assert_match /^250 2.6.0/, read

    request "QUIT"
    assert_match /^221 2.0.0/, read

    assert_equal finalmail(email), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}
  end

  def test_multiple_recipients
    assert_match /^220 /, read

    request "LHLO localhost"
    read

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "RCPT TO:<jones@foo.edu>"
    request "RCPT TO:<green@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request email
    assert_match /^250 2.6.0/, read

    request "QUIT"
    assert_match /^221 2.0.0/, read

    assert_equal finalmail(email), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}
  end

  def test_regular_rset
    assert_match /^220 /, read

    request "LHLO localhost"
    read

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request email
    assert_match /^250 2.6.0/, read

    request "RSET"
    assert_match /220 2.0.0/, read

    assert_equal finalmail(email), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request email
    assert_match /^250 2.6.0/, read

    request "QUIT"
    assert_match /^221 2.0.0/, read

    assert_equal finalmail(email), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}
  end

  def test_irregular_rset
    assert_match /^220 /, read

    request "LHLO localhost"
    read

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "RSET"
    assert_match /^220 2.0.0/, read

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request email
    assert_match /^250 2.6.0/, read

    request "QUIT"
    assert_match /^221 2.0.0/, read

    assert_equal finalmail(email), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}
  end

  def test_missing_quit
    assert_match /^220 /, read

    request "LHLO localhost"
    read

    request "MAIL FROM:<chris@bar.com>"
    request "RCPT TO:<pat@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request email
    assert_match /^250 2.6.0/, read

    @socket.close
    sleep 1
    # We should NOT see an exception in the server thread here.

    assert_equal finalmail(email), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}
  end

  def test_8bit
    assert_match /^220 /, read

    request "LHLO localhost"
    read

    request "MAIL FROM:<chris@bar.com> BODY=8BITMIME"
    request "RCPT TO:<pat@foo.edu>"
    request "DATA"
    assert_match /^250 2.1.0/, read
    assert_match /^250 2.1.0/, read
    assert_match /^354 /, read

    request binaryemail
    assert_match /^250 2.6.0/, read

    request "QUIT"
    assert_match /^221 2.0.0/, read

    assert_equal finalmail(binaryemail).force_encoding("BINARY"), File.open(TEMPMAIL_PATH, "rb"){|f| f.read}
  end

  private

  def request(cmd)
    @socket.write(cmd.strip.gsub("\n", "\r\n") + "\r\n")
  end

  def read
    result = ""
    loop do
      line = @socket.gets
      result << line.gsub("\r\n", "\n")
      break if line[3] != "-"
    end

    result
  end

  def email
    <<-EOF
From: chris@bar.com
To: pat@foo.edu
Subject: Test

Text line 1
Text line 2
.
    EOF
  end

  def binaryemail
    <<-EOF
From: chris@bar.com
To: pat@foo.edu
Subject: Test

Äöüßẞfoo.
.
    EOF
  end

  def finalmail(mail)
    mail.gsub("\n", "\r\n")[0..-4] # ommit .
  end

end
