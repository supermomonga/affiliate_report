# encoding: utf-8
require 'bundler'
Bundler.require
Dotenv.load
$:.unshift File.dirname(__FILE__)

ENV['PATH'] += ":" + File.expand_path(File.dirname(__FILE__))

class App < Thor

  def initialize *args
    @a = Mechanize.new
    @a.verify_mode = OpenSSL::SSL::VERIFY_NONE
    @asps = [:imobile, :addeluxe]
    @asps = [:imobile]
    super
  end

  desc 'y', "Show yesterday's report"
  def y
    yesterday = DateTime.now.to_date - 1
    print_reports yesterday..yesterday
  end

  desc 't', "Show today's report"
  def t
    today = DateTime.now.to_date
    print_reports today..today
  end

  private
  def print_reports term
    reports = @asps.select{|asp|
      ENV['ASP_ID_' + asp.to_s.upcase] && ENV['ASP_PW_' + asp.to_s.upcase]
    }.map{|asp|
      method(asp).call ENV['ASP_ID_' + asp.to_s.upcase], ENV['ASP_PW_' + asp.to_s.upcase], term
    }
    reports.push Report.new 'Total', term, reports.map(&:fee).inject(&:+)
    reports.each do |report|
      puts report
    end
  end
  def new_browser
    caps = Selenium::WebDriver::Remote::Capabilities.chrome
    caps['chromeOptions'] = {prefs: { webkit: { webprefs: { loads_images_automatically: false} } } }
    b = Watir::Browser.new :chrome, desired_capabilities: caps
    b.driver.manage.window.resize_to(0,0)
    b.driver.manage.window.move_to(0,0)
    b
  end
  def imobile id, pw, term
    b = new_browser
    b.goto 'https://sppartner.i-mobile.co.jp/login.aspx'
    b.text_field(:name, 'ctl00$ContentPlaceHolder2$Login1$UserName').value = id
    b.text_field(:name, 'ctl00$ContentPlaceHolder2$Login1$Password').value = pw
    b.button(:name, 'ctl00$ContentPlaceHolder2$Login1$LoginButton').click
    b.wait
    b.goto "https://sppartner.i-mobile.co.jp/report_detail.aspx?reportGroup=1&tsp=1&span=0&begin=%s&end=%s" % [ term.first.strftime("%Y-%m-%d"), term.last.strftime("%Y-%m-%d") ]
    b.wait
    fee = b.table(:class, 'List').to_a.reverse[1].last.tr('￥,','').to_i
    b.close
    Report.new 'i-mobile', term, fee
  end

  def addeluxe id, pw, term
    @a.post 'http://addeluxe.jp/login.php', {
      url: '',
      email1: id,
      passwd: pw,
      auto: '1'
    }
    res = @a.get 'http://addeluxe.jp/owner/pay_history.php', {
      y: term.first.year,
      m: term.first.month
    }
    fee = res.search('.tblPayHistoryOwner tr').select{|row|
      date = row.at('td')
      date && term.include?(Date.parse(date.text))
    }.inject(0){|acc, row|
      acc + row.search('td')[3].text.tr('¥,','').to_i
    }
    Report.new 'AdDeluxe', term, fee
  end

  class Report
    attr_reader :fee

    def initialize asp, term, fee
      @asp = asp
      @term = term
      @fee = fee
    end

    def to_s
      if @term.to_a.size == 1
        term = @term.first.strftime("%Y年%m月%d日")
      else
        term = [@term.first.strftime("%Y年%m月%d日"), @term.last.strftime("%Y年%m月%d日")].join ' - '
      end
      <<-EOF
#{@asp}:
  #{term}
  #{@fee}円

      EOF
    end

  end

end

App.start ARGV
