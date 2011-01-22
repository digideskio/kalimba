require 'camping'
require 'embedly'
require 'open-uri'
require 'hpricot'
require 'json'
require 'digest/sha1'
require 'ostruct'

# PUNK
class OpenStruct
  def type
    method_missing :type
  end
end

Camping.goes :Kalimba

#module Kalimba
#  include Camping::Session
#end

module Kalimba::Models
  class Article < Base
  end

  class Preview < Base
    def self._key url
      Digest::SHA1.hexdigest(url)
    end

    def self.key_exists? url
      find_redirect(url) or find_preview(url)
    end

    def self.find_redirect url
      key = "r::#{_key url}"
      find(:first, :conditions => {:key => key})
    end

    def self.find_preview url
      key = "p::#{_key url}"
      prev = find(:first, :conditions => {:key => key})
      return prev if prev
      if redirect = find_redirect(url)
        return find_preview(redirect.value)
      else
        nil
      end
    end

    def self.save_preview requested_url, preview
      if preview.url != requested_url
        key = "r::#{_key requested_url}"
        # does the redirect exist?
        r = find(:first, :conditions => { :key => key })
        # it does, so update if needed
        if r and r.value != preview.url
          r.value = preview.url
          r.save
        # nope, let's created it
        else
          create :key => key, :value => preview.url
        end
      end

      key = "p::#{_key preview.url}"
      create :key => key, :value => preview.marshal_dump.to_json
    end
  end

  class CreateTables < V 0.1
    def self.up
      create_table Article.table_name do |t|
        t.integer :rank
        t.string :title
        t.string :link
        t.string :comments
      end

      create_table Preview.table_name do |t|
        t.string :key
        t.string :value
        t.timestamps
      end
    end

    def self.down
      drop_table Article.table_name
    end
  end
end

module Kalimba::Controllers
  class Index < R '/'
    def get
      @articles = []
      Article::find(:all, :order => 'id').each do |a|
        preview = Preview.find_preview(a.link).value
        @articles << [a, OpenStruct.new(JSON.parse(preview))]
      end

      render :list_articles
    end
  end

  class Update < R '/update'
    def get
      Article.delete_all

      articles = []
      doc = Hpricot(open('http://news.ycombinator.com/'))
      (doc/'.subtext/..').each do |subtext|
        article = subtext.previous_node
        articles << {
          :rank => article.at('.title').inner_html,
          :title => article.at('.title/a').inner_html,
          :link => article.at('.title/a')[:href],
          :comments => "http://news.ycombinator.com/#{subtext.at('a:last')[:href]}"
        }
      end

      urls = articles.collect {|a| a[:link]}.reject {|a| Preview.key_exists? a}
      api = ::Embedly::API.new :key => '409326e2259411e088ae4040f9f86dcd'
      api.preview(:urls => urls).each_with_index do |preview, i|
        Preview.save_preview urls[i], preview
      end

      Article.create articles


      redirect R(Index)
=begin
      topic = @input.topic
      open(topic) do |s|
        RSS::Parser.parse(s.read).items.each_with_index do |item, i|
          Article.create(
            :rank => i,
            :title => item.title,
            :link => item.link,
            :comments => item.comments
          )
        end
      end
=end
    end
  end

  class Stylesheet < R '/css/main.css'
    def get
      @headers['Content-Type'] = 'text/css'
      File.read(__FILE__).gsub(/.*__END__/m, '')
    end
  end
end

module Kalimba::Views
  def layout
    html do
      head do
        title { "Kalimba - Rose Colored Glasses for Hacker News" }
        link :href => R(Stylesheet), :type => 'text/css', :rel => 'stylesheet'
        script(:src => 'http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js') {}
        script do
          self <<<<-'SCRIPT'
          jQuery(document).ready(function($) {
            $('.embedly_toggle').each(function() {
              var self = $(this);
              self.find('.toggle_button').click(function() {
                self.find('.embedly').toggle();
                return false;
              });
            });
          });
          SCRIPT
        end
      end

      body { self << yield }
    end
  end

  def list_articles
    ul.article_list do
      @articles.each do |article, preview|
        li.article do
          self << "Rank: #{article.rank} "
          a.article_link article.title, :href => article.link
          br
          a.comment_link 'Comments', :href => article.comments
          div do
    #        h1 'preview'
    #        pre(JSON.pretty_generate(preview.marshal_dump))
            _embed(preview)
          end
        end
      end
    end
  end

  def article
    ul do
      li @article.title
      li @article.url
      li @article.author
    end
  end

  # Too complicated
  def _content preview
    case preview.type
    when 'image'
      a.embedly_thumbnail(:href => preview.original_url) do
        img :src => preview.url
      end
    when 'video'
      video.embedly_video :src => preview.url, :controls => "controls", :preload => "preload"
    when 'audio'
      audio.embedly_video :src => preview.url, :controls => "controls", :preload => "preload"
    else
      if preview.content
        span.embedly_title do
          a preview.title, :target => '_blank', :href => preview.url
          p { preview.content }
        end
      else
        case preview.object['type']
        when 'photo'
          a.embedly_thumbnail :href => preview.original_url do
            img :src => preview.object_url
          end
        when 'video', 'rich'
          div { preview.object['html'] }
        else
          if preview.type == 'html'
            if preview.images.length != 0
              if preview.images.first['width'] >= 450
                a.embedly_thumbnail :target => '_blank', :href => preview.original_url, :title => preview.url do
                  img :src => preview.images.first['url']
                end
              else
                a.embedly_thumbnail_small :target => '_blank', :href => preview.original_url, :title => preview.url do
                  img :src => preview.images.first['url']
                end
              end
            end

            a.embedly_title preview.title, :target => '_blank', :href => preview.original_url, :title => preview.url
            p preview.description

            div { preview.embeds.first['html'] if preview.embeds.length > 0 }
          end
        end
      end
    end
  end

  def _embed preview
    div.embedly_toggle do
      a.toggle_button 'click me', :href => '#'
      div.embedly { _content preview }
    end
  end
end

def Kalimba.create
  #Camping::Models::Session.create_schema
  Kalimba::Models.create_schema
end

__END__
.embedly { display: none; }
