require File.dirname(__FILE__) + '/assertions'
require File.dirname(__FILE__) + '/deprecated_assertions'

module ActionController #:nodoc:
  class Base
    # Process a test request called with a +TestRequest+ object.
    def self.process_test(request)
      new.process_test(request)
    end
  
    def process_test(request) #:nodoc:
      process(request, TestResponse.new)
    end
  end

  class TestRequest < AbstractRequest #:nodoc:
    attr_accessor :cookies
    attr_accessor :query_parameters, :request_parameters, :path, :session, :env
    attr_accessor :host

    def initialize(query_parameters = nil, request_parameters = nil, session = nil)
      @query_parameters   = query_parameters || {}
      @request_parameters = request_parameters || {}
      @session            = session || TestSession.new
      
      initialize_containers
      initialize_default_values

      super()
    end

    def reset_session
      @session = {}
    end    

    def port=(number)
      @env["SERVER_PORT"] = number.to_i
    end

    def action=(action_name)
      @query_parameters.update({ "action" => action_name })
      @parameters = nil
    end
    
    # Used to check AbstractRequest's request_uri functionality.
    # Disables the use of @path and @request_uri so superclass can handle those.
    def set_REQUEST_URI(value)
      @env["REQUEST_URI"] = value
      @request_uri = nil
      @path = nil
    end

    def request_uri=(uri)
      @request_uri = uri
      @path = uri.split("?").first
    end

    def remote_addr=(addr)
      @env['REMOTE_ADDR'] = addr
    end

    def request_uri
      @request_uri || super()
    end

    def path
      @path || super()
    end
    
    def assign_parameters(parameters)
      path, extras = ActionController::Routing::Routes.generate(parameters.symbolize_keys)
      non_path_parameters = (get? ? query_parameters : request_parameters)
      parameters.each do |key, value|
        (extras.key?(key.to_sym) ? non_path_parameters : path_parameters)[key] = value
      end
    end

    private
      def initialize_containers
        @env, @cookies = {}, {}
      end
    
      def initialize_default_values
        @host                    = "test.host"
        @request_uri             = "/"
        self.remote_addr         = "0.0.0.0"        
        @env["SERVER_PORT"]      = 80
      end
  end
  
  class TestResponse < AbstractResponse #:nodoc:
    # the response code of the request
    def response_code
      headers['Status'][0,3].to_i rescue 0
    end
   
    # was the response successful?
    def success?
      response_code == 200
    end

    # was the URL not found?
    def missing?
      response_code == 404
    end

    # were we redirected?
    def redirect?
      (300..399).include?(response_code)
    end
    
    # was there a server-side error?
    def error?
      (500..599).include?(response_code)
    end

    alias_method :server_error?, :error?

    # returns the redirection location or nil
    def redirect_url
      redirect? ? headers['location'] : nil
    end
    
    # does the redirect location match this regexp pattern?
    def redirect_url_match?( pattern )
      return false if redirect_url.nil?
      p = Regexp.new(pattern) if pattern.class == String
      p = pattern if pattern.class == Regexp
      return false if p.nil?
      p.match(redirect_url) != nil
    end
   
    # returns the template path of the file which was used to
    # render this response (or nil) 
    def rendered_file(with_controller=false)
      unless template.first_render.nil?
        unless with_controller
          template.first_render
        else
          template.first_render.split('/').last || template.first_render
        end
      end
    end

    # was this template rendered by a file?
    def rendered_with_file?
      !rendered_file.nil?
    end

    # a shortcut to the flash (or an empty hash if no flash.. hey! that rhymes!)
    def flash
      session['flash'] || {}
    end
    
    # do we have a flash? 
    def has_flash?
      !session['flash'].empty?
    end

    # do we have a flash that has contents?
    def has_flash_with_contents?
      !flash.empty?
    end

    # does the specified flash object exist?
    def has_flash_object?(name=nil)
      !flash[name].nil?
    end

    # does the specified object exist in the session?
    def has_session_object?(name=nil)
      !session[name].nil?
    end

    # a shortcut to the template.assigns
    def template_objects
      template.assigns || {}
    end
   
    # does the specified template object exist? 
    def has_template_object?(name=nil)
      !template_objects[name].nil?      
    end
    
    # Returns the response cookies, converted to a Hash of (name => CGI::Cookie) pairs
    # Example:
    # 
    # assert_equal ['AuthorOfNewPage'], r.cookies['author'].value
    def cookies
      headers['cookie'].inject({}) { |hash, cookie| hash[cookie.name] = cookie; hash }
    end

    # Returns binary content (downloadable file), converted to a String
    def binary_content
      raise "Response body is not a Proc: #{body.inspect}" unless body.kind_of?(Proc)
      require 'stringio'

      sio = StringIO.new

      begin 
        $stdout = sio
        body.call
      ensure
        $stdout = STDOUT
      end

      sio.rewind
      sio.read
    end
end

  class TestSession #:nodoc:
    def initialize(attributes = {})
      @attributes = attributes
    end

    def [](key)
      @attributes[key]
    end

    def []=(key, value)
      @attributes[key] = value
    end
    
    def session_id
      ""
    end
    
    def update() end
    def close() end
    def delete() @attributes = {} end
  end
end

module Test
  module Unit
    class TestCase #:nodoc:
      private  
        # execute the request and set/volley the response
        def process(action, parameters = nil, session = nil, flash = nil)
          # Sanity check for required instance variables so we can give an understandable error message.
          %w(controller request response).each do |iv_name|
            assert_not_nil instance_variable_get("@#{iv_name}"), "@#{iv_name} is nil: make sure you set it in your test's setup method."
          end

          @html_document = nil
          @request.env['REQUEST_METHOD'] ||= "GET"
          @request.action = action.to_s

          parameters ||= {}
          parameters[:controller] = @controller.class.controller_path
          parameters[:action] = action.to_s
          @request.assign_parameters(parameters)

          @request.session = ActionController::TestSession.new(session) unless session.nil?
          @request.session["flash"] = ActionController::Flash::FlashHash.new.update(flash) if flash
          build_request_uri(action, parameters)
          @controller.process(@request, @response)
        end
    
        # execute the request simulating a specific http method and set/volley the response
        %w( get post put delete head ).each do |method|
          class_eval <<-EOV
            def #{method}(action, parameters = nil, session = nil, flash = nil)
              @request.env['REQUEST_METHOD'] = "#{method.upcase}"
              process(action, parameters, session, flash)
            end
          EOV
        end

        def xml_http_request(request_method, action, parameters = nil, session = nil, flash = nil)
          @request.env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest'
          self.send(request_method, action, parameters, session, flash)
        end
        alias xhr :xml_http_request

        def follow_redirect
          if @response.redirected_to[:controller]
            raise "Can't follow redirects outside of current controller (#{@response.redirected_to[:controller]})"
          end
          
          get(@response.redirected_to.delete(:action), @response.redirected_to.stringify_keys)
        end

        def assigns(key = nil)
          if key.nil?
            @response.template.assigns
          else
            @response.template.assigns[key.to_s]
          end
        end
        
        def session
          @response.session
        end

        def flash
          @response.flash
        end

        def cookies
          @response.cookies
        end

        def redirect_to_url
          @response.redirect_url
        end

        def build_request_uri(action, parameters)
          return if @request.env['REQUEST_URI']
          url = ActionController::UrlRewriter.new(@request, parameters)
          @request.set_REQUEST_URI(
            url.rewrite(@controller.send(:rewrite_options,
              (parameters||{}).update(:only_path => true, :action=>action))))
        end

        def html_document
          require_html_scanner
          @html_document ||= HTML::Document.new(@response.body)
        end
        
        def find_tag(conditions)
          html_document.find(conditions)
        end

        def find_all_tag(conditions)
          html_document.find_all(conditions)
        end

        def require_html_scanner
          return true if defined?(HTML::Document)
          require 'html/document'
        rescue LoadError
          $:.unshift File.dirname(__FILE__) + "/vendor/html-scanner"
          require 'html/document'
        end
        
        def method_missing(selector, *args)
          return @controller.send(selector, *args) if ActionController::Routing::NamedRoutes::Helpers.include?(selector)
          return super
        end
    end
  end
end
