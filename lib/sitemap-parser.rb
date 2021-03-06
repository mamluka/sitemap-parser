require 'nokogiri'
require 'typhoeus'

class SitemapParser

  def initialize(url, opts = {})
    @url = url
    @options = {:followlocation => true, :recurse => false, :url_regex => nil,threads: 8}.merge(opts)
  end

  def raw_sitemap
    @raw_sitemap ||= begin
      if @url =~ /\Ahttp/i
        request_options = @options.dup.tap { |opts| opts.delete(:recurse); opts.delete(:url_regex) ; opts.delete(:threads) }
        request = Typhoeus::Request.new(@url, request_options)
        request.on_complete do |response|
          if response.success?
            return response.body
          elsif response.code == 404
            return nil
          else
            raise "HTTP request to #{@url} failed"
          end
        end
        request.run
      elsif File.exist?(@url) && @url =~ /[\\\/]sitemap\.xml\Z/i
        open(@url) { |f| f.read }
      end
    end
  end

  def sitemap
    @sitemap ||= raw_sitemap ? Nokogiri::XML(raw_sitemap) : nil
  end

  def urls
  return [] if not sitemap
  if sitemap.at('urlset')
      filter_sitemap_urls(sitemap.at("urlset").search("url"))
    elsif sitemap.at('sitemapindex')
      found_urls = []
      if @options[:recurse]
        urls = sitemap.at('sitemapindex').search('sitemap')
        filter_sitemap_urls(urls).peach(@options[:threads]) do |sitemap|
          child_sitemap_location = sitemap.at('loc').content.gsub('.gz','')
          found_urls << self.class.new(child_sitemap_location, :recurse => false).urls
        end
      end
      return found_urls.flatten
    else
      p 'Malformed sitemap, no urlset'
      return []
    end
  end

  def to_a
    urls.map { |url| url.at("loc").content }
  rescue NoMethodError
    raise 'Malformed sitemap, url without loc'
  end

  private

  def filter_sitemap_urls(urls)
    return urls if @options[:url_regex].nil?
    urls.select {|url| url.at("loc").content.strip =~ @options[:url_regex] }
  end
end
