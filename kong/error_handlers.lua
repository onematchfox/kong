local meta = require "kong.meta"
local singletons = require "kong.singletons"
local constants = require "kong.constants"
local helpers = require("kong.plugins.revolution.helpers")
local cjson = require "cjson"
local to_hex = require "resty.string".to_hex

local find = string.find
local format = string.format

local TYPE_PLAIN = "text/plain"
local TYPE_JSON = "application/json"
local TYPE_XML = "application/xml"
local TYPE_HTML = "text/html"

local text_template = "%s"
local json_template = '{"request_id": "%s", "message":"%s"}'
local xml_template = '<?xml version="1.0" encoding="UTF-8"?>\n<error><request_id>%s</request_id><message>%s</message></error>'
local html_template = '<html><head><title>Revolution Error</title></head><body><h1>Revolution Error</h1><p><b>Request Id: </b>%s</p><p><b>Message: </b>%s</p></body></html>'

local HEADERS = {
  s400 = "Bad Request",
  s401 = "Unauthorized",
  s402 = "Payment Required",
  s403 = "Forbidden",
  s404 = "Not Found",
  s405 = "Method Not Allowed",
  s406 = "Not Acceptable",
  s407 = "Proxy Authentication Required",
  s408 = "Request Timeout",
  s409 = "Conflict",
  s410 = "Gone",
  s411 = "Length Required",
  s412 = "Precondition Failed",
  s413 = "Payload Too Large",
  s414 = "URI Too Long",
  s415 = "Unsupported Media Type",
  s416 = "Range Not Satisfiable",
  s417 = "Expectation Failed",
  s418 = "I'm a teapot",
  s421 = "Misdirected Request",
  s422 = "Unprocessable Entity",
  s423 = "Locked",
  s424 = "Failed Dependency",
  s426 = "Upgrade Required",
  s428 = "Precondition Required",
  s429 = "Too Many Requests",
  s431 = "Request Header Fields Too Large",
  s451 = "Unavailable For Legal Reasons",
  s500 = "Internal Server Error",
  s501 = "Not Implemented",
  s502 = "Bad Gateway",
  s503 = "Service Unavailable",
  s504 = "Gateway Timeout",
  s505 = "HTTP Version Not Supported",
  s506 = "Variant Also Negotiates",
  s507 = "Insufficient Storage",
  s508 = "Loop Detected",
  s510 = "Not Extended",
  s511 = "Network Authentication Required",
  s599 = "Network Connect Timeout Error",
  default = "%d"
}

local BODIES = {
  s400 = "The server cannot or will not process the request due to something that is perceived to be a client error (e.g. malformed request syntax, invalid request message framing, or deceptive request routing).",
  s401 = "The request has not been applied because it lacks valid authentication credentials for the target resource.",
  s402 = "Reserved for future use.",
  s403 = "The server understood the request but refuses to authorize it.",
  s404 = "The origin server did not find a current representation for the target resource or is not willing to disclose that one exists.",
  s405 = "The method received in the request-line is known by the origin server but not supported by the target resource.",
  s406 = "The target resource does not have a current representation that would be acceptable to the user agent, according to the proactive negotiation header fields received in the request1, and the server is unwilling to supply a default representation.",
  s407 = "Similar to 401 Unauthorized, but it indicates that the client needs to authenticate itself in order to use a proxy.",
  s408 = "The server did not receive a complete request message within the time that it was prepared to wait.",
  s409 = "The request could not be completed due to a conflict with the current state of the target resource. This code is used in situations where the user might be able to resolve the conflict and resubmit the request.",
  s410 = "The target resource is no longer available at the origin server and that this condition is likely to be permanent.",
  s411 = "The server refuses to accept the request without a defined Content-Length1.",
  s412 = "One or more conditions given in the request header fields evaluated to false when tested on the server.",
  s413 = "The server is refusing to process a request because the request payload is larger than the server is willing or able to process.",
  s414 = "The server is refusing to service the request because the request-target is longer than the server is willing to interpret.",
  s415 = "The origin server is refusing to service the request because the payload is in a format not supported by this method on the target resource.",
  s416 = "None of the ranges in the request's Range header field1 overlap the current extent of the selected resource or that the set of ranges requested has been rejected due to invalid ranges or an excessive request of small or overlapping ranges.",
  s417 = "The expectation given in the request's Expect header field1 could not be met by at least one of the inbound servers.",
  s418 = "Any attempt to brew coffee with a teapot should result in the error code \"418 I'm a teapot\". The resulting entity body MAY be short and stout.",
  s421 = "The request was directed at a server that is not able to produce a response. This can be sent by a server that is not configured to produce responses for the combination of scheme and authority that are included in the request URI.",
  s422 = "The server understands the content type of the request entity (hence a 415 Unsupported Media Type status code is inappropriate), and the syntax of the request entity is correct (thus a 400 Bad Request status code is inappropriate) but was unable to process the contained instructions.",
  s423 = "The source or destination resource of a method is locked.",
  s424 = "The method could not be performed on the resource because the requested action depended on another action and that action failed.",
  s426 = "The server refuses to perform the request using the current protocol but might be willing to do so after the client upgrades to a different protocol.",
  s428 = "The origin server requires the request to be conditional.",
  s429 = "The user has sent too many requests in a given amount of time (\"rate limiting\").",
  s431 = "The server is unwilling to process the request because its header fields are too large. The request MAY be resubmitted after reducing the size of the request header fields.",
  s444 = "A non-standard status code used to instruct nginx to close the connection without sending a response to the client, most commonly used to deny malicious or malformed requests.",
  s451 = "The server is denying access to the resource as a consequence of a legal demand.",
  s500 = "The server encountered an unexpected condition that prevented it from fulfilling the request.",
  s501 = "The server does not support the functionality required to fulfill the request.",
  s502 = "The server, while acting as a gateway or proxy, received an invalid response from an inbound server it accessed while attempting to fulfill the request.",
  s503 = "The server is currently unable to handle the request due to a temporary overload or scheduled maintenance, which will likely be alleviated after some delay.",
  s504 = "The server, while acting as a gateway or proxy, did not receive a timely response from an upstream server it needed to access in order to complete the request.",
  s505 = "The server does not support, or refuses to support, the major version of HTTP that was used in the request message.",
  s506 = "The server has an internal configuration error: the chosen variant resource is configured to engage in transparent content negotiation itself, and is therefore not a proper end point in the negotiation process.",
  s507 = "The method could not be performed on the resource because the server is unable to store the representation needed to successfully complete the request.",
  s508 = "The server terminated an operation because it encountered an infinite loop while processing a request with \"Depth: infinity\". This status indicates that the entire operation failed.",
  s510 = "The policy for accessing the resource has not been met in the request. The server should send back all the information necessary for the client to issue an extended request.",
  s511 = "The client needs to authenticate to gain network access.",
  s599 = "This status code is not specified in any RFCs, but is used by some HTTP proxies to signal a network connect timeout behind the proxy to a client in front of the proxy."
}

local SERVER_HEADER = meta._SERVER_TOKENS

local function parse_accept_header(headers)
  local accept_header = headers["accept"]
  local template, content_type

  if accept_header == nil then
    accept_header = singletons.configuration.error_default_type
  end

  if find(accept_header, TYPE_HTML, nil, true) then
    template = html_template
    content_type = TYPE_HTML
  elseif find(accept_header, TYPE_JSON, nil, true) then
    template = json_template
    content_type = TYPE_JSON
  elseif find(accept_header, TYPE_XML, nil, true) then
    template = xml_template
    content_type = TYPE_XML
  else
    template = text_template
    content_type = TYPE_PLAIN
  end

  return template, content_type
end

local function transform_custom_status_codes(status_code)
  -- Non-standard 4XX HTTP codes will be returned as 400 Bad Request
  if status_code > 451 and status_code < 500 then
    status_code = 400
  end

  return status_code
end

return function(ngx)
  local ctx = ngx.ctx
  local headers = ngx.req.get_headers()
  local template, content_type = parse_accept_header(headers)

  local status = transform_custom_status_codes(ngx.status)
  local title = status..": "..(HEADERS["s" .. status] or format(HEADERS.default, status))

  -- Attempt to read body (message) and headers from ctx for internal/plugin errors generated via kong.response.exit(...)
  local data = ctx.error_body
  local brand = ctx.brand or "statpro"
  local message = data and data.message or BODIES["s" .. status] or format(HEADERS.default, status)

  if not ngx.headers_sent and type(ctx.error_headers) == 'table' then
    for k,v in pairs(ctx.error_headers) do
      ngx.header[k] = v
    end
  end

  local request_id = ctx.trace_context and to_hex(ctx.trace_context.trace_id)
    or headers["Cf-Ray"] or headers["X-Amzn-Trace-Id"]
    or headers["X-Revolution-Session-Id"] or headers["shib-session-id"] or ""

  ctx.ERROR_HANDLED = true

  ngx.header["Content-Type"] = content_type

  if content_type == TYPE_HTML then
    local custom_html_template = require "resty.template"
    custom_html_template.render(brand.."/error.html", { title = title, brand = brand, user_details = data and data.user_details, message = message, request_id = request_id, status = status })
  else
    ngx.say(format(template, request_id, message))
  end
end
