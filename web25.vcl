
    # Doc: Called at the beginning of a request, after the complete request 
    #      has been received and parsed. Its purpose is to 
    #      decide whether or not to serve the request, how to 
    #      do it, and, if applicable, which backend to use.
sub vcl_recv {
#FASTLY recv

  # Handle grace periods for where we will serve a stale response
  #     source: https://github.com/python/psf-fastly/blob/master/vcl/pypi.vcl
  if (!req.backend.healthy) {
      # The backend is unhealthy which means we want to serve the stale
      #   response long enough (hopefully) for us to fix the problem.
      set req.grace = 24h;

      # The backend is unhealthy which means we want to serve responses as
      #   if the user was not logged in. This means they will be eligible
      #   for the cached pages.
      remove req.http.Authenticate;
      remove req.http.Authorization;
      remove req.http.Cookie;
  }
  else {
      # Avoid a request pileup by serving stale content if required.
      set req.grace = 15s;
  }

  # Strip Cookies and Authentication headers from urls whose output will
  #   never be influenced by them.
  #   source: https://github.com/python/psf-fastly/blob/master/vcl/pypi.vcl
  if (req.url ~ "^/(wp-content|wp-includes)") {
      remove req.http.Authenticate;
      remove req.http.Authorization;
      remove req.http.Cookie;
  }

  ## Fastly BOILERPLATE ========
  #  # NOTE: To use vcl_miss in some desired cases, pass everything to lookup, not pass
  #  #       ref: http://stackoverflow.com/questions/5110841/is-there-a-way-to-set-req-connection-timeout-for-specific-requests-in-varnish
  #  if (req.request != "HEAD" && req.request != "GET" && req.request != "PURGE") {
  #    return(pass);
  #  }
    return(lookup);  # Default outcome, keep at the end
  ## /Fastly BOILERPLATE ========
}


    # Doc: Called after a document has been successfully retrieved from the backend
sub vcl_fetch {
#FASTLY fetch

  # Set the maximum grace period on an object
  set beresp.grace = 24h;

  # Gzip
  if (beresp.status == 200 && (beresp.http.content-type ~ "^(text/html|application/x-javascript|text/css|application/javascript|text/javascript)\s*($|;)" || req.url ~ "\.(js|css|html)($|\?)" ) ) {

    # always set vary to make sure uncompressed versions dont always win
    if (!beresp.http.Vary ~ "Accept-Encoding") {
      if (beresp.http.Vary) {
        set beresp.http.Vary = beresp.http.Vary ", Accept-Encoding";
      } else {
         set beresp.http.Vary = "Accept-Encoding";
      }
    }
    if (req.http.Accept-Encoding == "gzip") {
      set beresp.gzip = true;
    }
  }

  ## Fastly BOILERPLATE ========
  if ((beresp.status == 500 || beresp.status == 503) && req.restarts < 1 && (req.request == "GET" || req.request == "HEAD")) {
    restart;
  }
  if(req.restarts > 0 ) {
    set beresp.http.Fastly-Restarts = req.restarts;
  }
  if (beresp.http.Set-Cookie) {
    set req.http.Fastly-Cachetype = "SETCOOKIE";
    return (pass);
  }
  if (beresp.http.Cache-Control ~ "private") {
    set req.http.Fastly-Cachetype = "PRIVATE";
    return (pass);
  }
  if (beresp.status == 500 || beresp.status == 503) {
    set req.http.Fastly-Cachetype = "ERROR";
    set beresp.ttl = 1s;
    set beresp.grace = 5s;
    return (deliver);
  }
  if (beresp.http.Expires || beresp.http.Surrogate-Control ~ "max-age" || beresp.http.Cache-Control ~"(s-maxage|max-age)") {
    # keep the ttl here
  } else {
    # apply the default ttl
    set beresp.ttl = 3600s;
  }
  return(deliver); # Default outcome, keep at the end
  ## /Fastly BOILERPLATE =======
}


    # Doc: Called before a cached object is delivered to the client
sub vcl_deliver {
#FASTLY deliver

  # Debug, Advise backend
  set resp.http.X-Debug-Backend-Key = req.backend;

  # Debug, what URL was requested
  set resp.http.X-Debug-Request-Url = req.url;

  # Debug, change version string
  set resp.http.X-Config-Serial = "2014030600";

  ## Fastly BOILERPLATE ========
  return(deliver);  # Default outcome, keep at the end
  ## /Fastly BOILERPLATE =======
}


    # Doc: Called after a cache lookup if the requested document was found in the cache.
sub vcl_hit {
#FASTLY hit

  ## Fastly BOILERPLATE ========
  if (!obj.cacheable) {
    return(pass); # Do NOT cache :(
  }
  return(deliver);  # Default outcome, keep at the end
  ## /Fastly BOILERPLATE =======
}


    # Doc: Called after a cache lookup if the 
    #      requested document was not found in 
    #      the cache. Its purpose is to decide 
    #      whether or not to attempt to retrieve 
    #      the document from the backend, and  
    #      which backend to use.
sub vcl_miss {
#FASTLY miss

  # Some backend calls can be longer than
  # page reads :(
  if (req.url ~ "^/backoffice") {
    set bereq.first_byte_timeout = 5m;
    set bereq.between_bytes_timeout = 3m;
  } 
  return(fetch); # Default outcome, keep at the end
}
