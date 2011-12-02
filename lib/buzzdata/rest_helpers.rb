module RestHelpers

  def handle_error(response)
    raise Buzzdata::Error.new if response.nil?
    parsed_error = JSON.parse(response.body)
    raise Buzzdata::Error.new(parsed_error['message'])
  end

  # Define methods for our HTTP verbs
  [:post, :put, :get, :delete].each do |method|

    module_eval <<-RUBY #, __FILE__, __LINE__

    def #{method}(url, params={})
      params['api_key'] = @api_key
      params = {:params => params} unless :#{method} == :post

      RestClient.send(:#{method}, url, params) do |response, request, result, &block|
        case response.code
        when 403, 404, 500
          handle_error(response)
        else
          response.return!(request, result, &block)
        end
      end
    end

    # Define methods for our verbs with json handling
    def #{method}_json(path, params={})
      response = send(:#{method}, path, params)
      JSON.parse(response.body)
    end

    RUBY

  end
  
  def raw_get(url)
    RestClient.get(url)
  end

end
