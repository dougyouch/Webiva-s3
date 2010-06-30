
class S3::AdminController < ModuleController


  component_info 'S3', :description => 'Adds support for S3 as a data store', 
                              :access => :private 
           
  register_handler :website, :file,  "S3::DomainFileSupport"
                  
  register_handler :page, :after_request, "S3::RequestHandler"

  def options
   cms_page_info [ ["Options",url_for(:controller => '/options') ], ["Modules",url_for(:controller => "/modules")], "S3 Options"], "options"
    
    @options = Configuration.get_config_model(ModuleOptions,params[:options])
    
    if request.post? && params[:options] && @options.valid?
      @options.clear_cloud_front_settings unless @options.valid_cloud_front_settings?
      Configuration.set_config_model(@options)
      flash[:notice] = "Updated S3 module settings".t 
      redirect_to :controller => '/modules'
      return
    end
  end

  def cloud_front_setup
    cms_page_info [ ["Options",url_for(:controller => '/options') ], ["Modules",url_for(:controller => "/modules")], ["S3 Options", url_for(:action => 'options')], "Cloud Front Setup"], "options"

    @options = Configuration.get_config_model(ModuleOptions,params[:options])
    unless @options.valid?
      flash[:notice] = "Invalid S3 settings".t 
      redirect_to :action => 'options' 
      return
    end

    begin
      @options.cloud_front.distributions
    rescue RightAws::AwsError
      flash[:notice] = 'AWS Cloud Front subscription is required for this access key'.t
      redirect_to :action => 'options' 
      return
    end

    if @options.cloud_front_distribution_info && @options.cloud_front_distribution_info[:status] == 'InProgress' && @options.cloud_front.deployed?
      @options.cloud_front_distribution_info = @options.cloud_front.distribution
      @options.enable_cloud_front = true
      Configuration.set_config_model(@options)
      flash[:notice] = 'AWS Cloud Front is setup'
      redirect_to :controller => '/modules'
      return
    end

    if request.post? && params[:options] && @options.valid?
      if @options.save_cloud_front_settings
        Configuration.set_config_model(@options)
        redirect_to :action => 'cloud_front_setup'
        return
      else
        @options.errors.add(:cname, 'is invalid or already in use')
      end
    end
  end

  class ModuleOptions < HashModel
    default_options :access_key_id => nil, :secret_access_key => nil, :bucket => nil, :enable_cloud_front => nil,
      :cloud_front_distribution_info => nil, :cname => nil

    boolean_options :enable_cloud_front

    validates_presence_of :access_key_id, :secret_access_key, :bucket

    def validate
      if self.access_key_id && self.secret_access_key && self.bucket
        # test the connection by making a request for the buckets
        buckets = nil
        begin
          buckets = self.connection.buckets
        rescue RightAws::AwsError
          self.errors.add(:access_key_id, 'is invalid')
          self.errors.add(:secret_access_key, 'is invalid')
        end

        if buckets
          if S3::Bucket.valid_bucket_name?(self.bucket)
            begin
              self.connection.bucket
            rescue RightAws::AwsError
              self.errors.add(:bucket, 'failed to create bucket')
            end
          else
            self.errors.add(:bucket, 'name is invalid')
          end
        end
      end
    end

    def connection
      @connection ||= S3::Bucket.new self.access_key_id, self.secret_access_key, self.bucket
    end

    def cloud_front
      return @cloud_front if @cloud_front
      aws_id = self.cloud_front_distribution_info ? self.cloud_front_distribution_info[:aws_id] : nil
      @cloud_front = S3::CloudFront.new self.connection, aws_id
    end

    def cloud_front_distribution_id
      self.cloud_front.distribution[:aws_id] if self.cloud_front.distribution
    end

    def cloud_front_domain_name
      self.cloud_front.distribution[:domain_name] if self.cloud_front.distribution
    end

    def cloud_front_origin
      self.cloud_front.distribution[:origin] if self.cloud_front.distribution
    end

    def cloud_front_status
      self.cloud_front.distribution[:status] if self.cloud_front.distribution
    end

    def cloud_front_cname
      if self.cloud_front.distribution && self.cloud_front.distribution[:cnames]
        self.cloud_front.distribution[:cnames][0]
      else
        ''
      end
    end

    def cnames
      self.cname.blank? ? [] : [self.cname]
    end

    def save_cloud_front_settings
      if self.cloud_front.save(self.cnames)
        self.enable_cloud_front = false
        self.cloud_front_distribution_info = self.cloud_front.distribution
        true
      else
        self.errors.add_to_base('Failed to save cloud front settings')
        false
      end
    end

    def clear_cloud_front_settings
      self.cloud_front_distribution_info = nil
      self.enable_cloud_front = nil
      self.cname = nil
    end

    def valid_cloud_front_settings?
      begin
        # Access Key has a cloud front subscription
        self.cloud_front.distributions
      rescue RightAws::AwsError
        return false
      end

      # make sure the bucket name is the same
      self.cloud_front.origin == self.cloud_front_origin
    end
  end

  def self.module_options
    Configuration.get_config_model(ModuleOptions)
  end
end

