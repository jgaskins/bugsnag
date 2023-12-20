require "http"
require "json"

# Bugsnag
# ```
# ```
module Bugsnag
  VERSION = "0.1.0"

  class_property api_key : String = ENV.fetch("BUGSNAG_API_KEY", "")

  # Notify Bugsnag of an exception
  #
  # ```
  # begin
  #   handle(thing)
  # rescue ex
  #   Bugsnag.notify ex,
  #     severity: Bugsnag::Event::Severity::Error,
  #     app: Bugsnag::App.new(
  #       id: "my-app",
  #       release_stage: ENV["DEPLOYMENT_ENVIRONMENT"]? || "development",
  #     ),
  #     metadata: Bugsnag::Metadata{"thing" => thing.to_h}
  # end
  # ```
  def self.notify(
    exception : ::Exception,
    request : HTTP::Request? = nil,
    severity : Event::Severity = Event::Severity::Warning,
    context : String? = nil,
    user : User? = nil,
    session : Session? = nil,
    metadata : Metadata? = nil,
    app : App? = nil
  )
    events = [
      Event.new(
        exceptions: [
          Exception.from_crystal_exception(exception),
        ],
        severity: severity,
        request: Request.from_http_request(request),
        context: context,
        user: user,
        session: session,
        metadata: metadata,
        app: app,
      ),
    ]

    Client.new.notify events
  end

  # Report errors that occur in your HTTP apps to Bugsnag automatically.
  #
  # ```
  # http = HTTP::Server.new([
  #   Bugsnag::Middleware.new
  #     .with_user { |context| Bugsnag::User.from_user(find_user_from(context)) }
  #     .with_app { Bugsnag::App.new(id: "my-app") }
  #     .with_metadata { |context| Bugsnag::Metadata{"session" => context.session.data} },
  #   my_app,
  # ])
  # ```
  class Middleware
    include HTTP::Handler

    alias Context = HTTP::Server::Context
    alias GetUser = Context -> User?
    alias GetMetadata = Context -> Metadata?
    alias GetApp = Context -> App?

    @get_user : GetUser
    @get_metadata : GetMetadata
    @get_app : GetApp

    def initialize(@api_key : String = Bugsnag.api_key)
      @get_user = GetUser.new { }
      @get_metadata = GetMetadata.new { }
      @get_app = GetApp.new { }
    end

    # Tell the Bugsnag middleware how to infer the user from the
    # `HTTP::Server::Context` for the current request.
    #
    # ```
    # Bugsnag::Middleware.new
    #   .with_user { |context| Bugsnag::User.from_user(context.current_user) }
    # ```
    def with_user(&@get_user : GetUser)
      self
    end

    # Tell the Bugsnag middleware what other information may be useful based on
    # the `HTTP::Server::Context` for the current request. For example, maybe
    # you want to include session data. The keys for a Metadata object must be
    # strings and the values must be JSON-serializable objects, such as
    # `JSON::Any` (or any type it can wrap) or an object that includes
    # `JSON::Serializable`.
    #
    # ```
    # Bugsnag::Middleware.new
    #   .with_metadata { |context| Bugsnag::Metadata{
    #     "session"     => context.session.data,
    #     "environment" => filter(hash_from(ENV)),
    #   } }
    # ```
    def with_metadata(&@get_metadata : GetMetadata)
      self
    end

    # Give the Bugsnag middleware information about the running app, including
    # the name, version, release stage (production, development, beta, etc),
    # and even how long it's been running.
    #
    # ```
    # started_at = Time.monotonic
    # Bugsnag::Middleware.new
    #   .with_app { |context| Bugsnag::App.new(
    #     id: "my-app-web",
    #     version: ENV["GIT_REF"]?,
    #     release_stage: ENV["DEPLOYMENT_ENVIRONMENT"]? || "development",
    #     duration: (Time.monotonic - started_at).total_milliseconds.to_i,
    #   ) }
    # ```
    #
    # For more details, see `Bugsnag::App`.
    def with_app(&@get_app : GetApp)
      self
    end

    # :nodoc:
    def call(context : HTTP::Server::Context)
      call_next context
    rescue exception
      spawn do
        Bugsnag.notify(
          exception: exception,
          request: context.request,
          severity: Event::Severity::Error,
          user: @get_user.call(context),
          metadata: @get_metadata.call(context),
          app: @get_app.call(context),
        )
      end
      raise exception
    end
  end

  class Client
    PAYLOAD_VERSION = "5"

    def initialize(
      @api_key : String = Bugsnag.api_key,
      @name = "Bugsnag Crystal",
      @version = VERSION,
      @notifier_project_url = "https://github.com/jgaskins/bugsnag",
      @notify_uri = URI.parse("https://notify.bugsnag.com/")
    )
    end

    def notify(events : Enumerable(Event)) : Nil
      body = {
        apiKey:         @api_key,
        payloadVersion: PAYLOAD_VERSION,
        notifier:       {
          name:    @name,
          version: @version,
          url:     @notifier_project_url,
        },
        events: events,
      }

      response = HTTP::Client.post(
        @notify_uri,
        headers: HTTP::Headers{
          "Bugsnag-Api-Key"         => @api_key,
          "Bugsnag-Payload-Version" => PAYLOAD_VERSION,
          "Bugsnag-Sent-At"         => Time::Format::ISO_8601_DATE_TIME.format(Time.utc),
        },
        body: body.to_json,
      )

      if response.success?
        # This is usually just the string "OK", so I don't think we need to do anything
      else
        raise "[Bugsnag] Cannot report to Bugsnag: #{response.body}"
      end
    end
  end

  struct Event
    include JSON::Serializable

    getter exceptions : Enumerable(Exception)
    getter breadcrumbs : Enumerable(Breadcrumb)?
    getter request : Request?
    # getter threads : Array(Thread)
    getter context : String?
    @[JSON::Field(key: "groupingHash")]
    getter grouping_hash : String?
    getter unhandled : Bool?
    getter severity : Severity?
    # getter severity_reason : SeverityReason
    getter user : User | NamedTuple(id: String?, name: String?, email: String?) | Nil
    getter app : App?
    # getter device : Device
    getter session : Session?
    @[JSON::Field(key: "metaData")]
    getter metadata : Metadata?

    def self.new(exceptions, request : HTTP::Request)
      request = Request.from_http_request(request)
      new(exceptions, request)
    end

    def initialize(
      @exceptions : Enumerable(Exception),
      @request : Request? = nil,
      @breadcrumbs = nil,
      @context = nil,
      @grouping_hash = nil,
      @unhandled = nil,
      @severity = nil,
      @user = nil,
      @app = nil,
      @session = nil,
      @metadata = nil
    )
    end

    enum Severity
      Error
      Warning
      Info

      def to_json(json : JSON::Builder)
        json.string to_s
      end
    end
  end

  # The user information to report to Bugsnag. Bugsnag lets you report which user
  # experienced this issue so you can see how many users were impacted by it in
  # the aggregate view and see what other issues that particular user is
  # experiencing.
  struct User
    include JSON::Serializable

    getter id : String?
    getter name : String?
    getter email : String?

    # If your own user model has getters for `id`, `name`, and `email`, you can
    # pass it to `Bugsnag::User.from_user` to convert your user to a
    # `Bugsnag::User` trivially.
    #
    # ```
    # struct MyAppUser
    #   getter id : UUID
    #   getter email : String
    #   getter name : String?
    #   # other details like how to instantiate it or fetch from the DB
    # end
    #
    # Bugsnag::User.from_user(my_app_user)
    # ```
    def self.from_user(user)
      new(id: user.id.try(&.to_s), name: user.name, email: user.email)
    end

    # Instantiate a `Bugsnag::User` with the given string `id`, `name`, and
    # `email` properties.
    #
    # ```
    # Bugsnag::User.new(id: "1234", email: "foo@example.com", name: "Foo Bar")
    # ```
    def initialize(@id, @name, @email)
    end
  end

  struct Session
    include JSON::Serializable

    getter id : String
    @[JSON::Field(key: "startedAt")]
    getter started_at : String
    getter events : Events

    def initialize(@id, @started_at, @events)
    end

    struct Events
      include JSON::Serializable

      getter handled : Int32
      getter unhandled : Int32

      def initialize(@handled, @unhandled)
      end
    end
  end

  # Information about your application that you want to provide for the purposes
  # of debugging, aggregating, or faceted search. The most common things you
  # will likely want to provide are the name of the app (`id`), the `version`,
  # the `release_stage` (`"production"`, `"staging"`, `"beta"`, etc), and the
  # `duration` (how long the app has been running).
  struct App
    include JSON::Serializable

    getter id : String?
    getter version : String?
    @[JSON::Field(key: "versionCode")]
    getter version_code : Int32?
    @[JSON::Field(key: "bundleVersion")]
    getter bundle_version : String?
    @[JSON::Field(key: "codeBundleId")]
    getter code_bundle_id : String?
    @[JSON::Field(key: "buildUUID")]
    getter build_uuid : String?
    @[JSON::Field(key: "releaseStage")]
    getter release_stage : String?
    getter type : String?
    @[JSON::Field(key: "dsymUUIDs")]
    getter dsym_uuids : String?
    getter duration : Int32?
    @[JSON::Field(key: "durationInForeground")]
    getter duration_in_foreground : Int32?
    @[JSON::Field(key: "inForeground")]
    getter in_foreground : Bool?
    @[JSON::Field(key: "binaryArch")]
    getter binary_arch : BinaryArch?

    def initialize(
      @id = nil,
      @version = nil,
      @version_code = nil,
      @bundle_version = nil,
      @code_bundle_id = nil,
      @build_uuid = nil,
      @release_stage = nil,
      @type = nil,
      @dsym_uuids = nil,
      @duration = nil,
      @duration_in_foreground = nil,
      @in_foreground = nil,
      @binary_arch = nil
    )
    end

    enum BinaryArch
      X86
      X86_64
      ARM32
      ARM64

      def to_json(json : JSON::Builder)
        json.string to_s.downcase
      end
    end
  end

  # The `Request` represents the HTTP or RPC request during which the exception
  # was raised.
  struct Request
    include JSON::Serializable

    @[JSON::Field(key: "clientIp")]
    getter client_ip : String?
    getter headers : HTTP::Headers?
    @[JSON::Field(key: "httpMethod")]
    getter http_method : String?
    getter url : String?
    getter referer : String?

    def self.from_http_request(request)
      scheme = request.headers.fetch("x-forwarded-proto", "http")
      host = request.headers["host"]?
      new(
        client_ip: request.remote_address.as(Socket::IPAddress).address,
        headers: request.headers,
        http_method: request.method,
        url: "#{scheme}://#{host}#{request.resource}",
        referer: request.headers["Referer"]?,
      )
    end

    def self.from_http_request(no_request : Nil)
    end

    def initialize(@client_ip, @headers, @http_method, @url, @referer)
    end
  end

  struct Breadcrumb
    include JSON::Serializable

    getter timestamp : Time
    getter name : String
    getter type : Type
    @[JSON::Field(key: "metaData")]
    getter metadata : Hash(String, JSON::Any::Type)?

    enum Type
      Navigation
      Request
      Process
      Log
      User
      State
      Error
      Manual

      def to_json(json : JSON::Builder)
        json.string inspect
      end
    end

    def initialize(@timestamp, @name, @type, @metadata)
    end
  end

  struct Exception
    include JSON::Serializable

    @[JSON::Field(key: "errorClass")]
    getter error_class : String

    getter message : String
    getter stacktrace : Enumerable(StackFrame)

    def self.from_crystal_exception(exception : ::Exception)
      new(
        error_class: exception.class.name,
        message: exception.message || "[No error message provided]",
        stacktrace: exception.backtrace.compact_map { |line|
          StackFrame.from_backtrace_line(line)
        }
      )
    end

    def initialize(@error_class, @message, @stacktrace)
    end
  end

  struct StackFrame
    include JSON::Serializable

    getter file : String
    @[JSON::Field(key: "lineNumber")]
    getter line_number : Int32
    @[JSON::Field(key: "columnNumber")]
    getter column_number : Int32?
    getter method : String
    @[JSON::Field(key: "inProject")]
    getter in_project : Bool
    getter code : Hash(Int32, String)

    def self.from_backtrace_line(line)
      # "../../../../usr/local/Cellar/crystal/0.35.1_1/src/http/server/handler.cr:28:7 in 'call_next'"

      if match = line.match(/(.+):(\d+):(\d+) in '(.+)'/)
        _, file, line_number, column_number, method = match
        in_project = file.starts_with?("src/") || file.starts_with?("views/")
        line_number = line_number.to_i
        column_number = column_number.to_i
        code = [""] + (File.read_lines(file) rescue %w[])
        start_of_code = {line_number - 3, 1}.max
        end_of_code = {line_number + 3, code.size - 1}.min
        code_hash = {} of Int32 => String
        (start_of_code..end_of_code).each_with_index(start_of_code) do |line, index|
          if text = code[line]?
            code_hash[index] = text
          end
        end

        StackFrame.new(
          file: file,
          line_number: line_number,
          column_number: column_number,
          method: method,
          in_project: in_project,
          code: code_hash,
        )
      end
    end

    def initialize(@file, @line_number, @column_number, @method, @in_project, @code)
    end
  end

  struct Metadata
    alias Value = JSON::Any::Type | JSON::Any | JSON::Serializable

    @raw = Hash(String, Value).new

    def []=(key, value)
      @raw[key] = value.as(Value)
    end

    def to_json(json : JSON::Builder)
      @raw.to_json json
    end
  end
end
