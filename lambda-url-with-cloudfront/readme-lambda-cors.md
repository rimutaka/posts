# AWS Lambda Function URL with CORS explained by example

This post explores different configuration options for invoking AWS Lambda functions via a URL.

## Overview

### Why we need Cross-Origin Resource Sharing (CORS) for Lambda Function URLs

AWS Lambda Functions can be invoked via a public [AWS Lambda Function URL](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html) with an HTTP call from a browser script, e.g.

```javascript
const lambdaResponse = await fetch(
  "https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/",
  {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  },
);
``` 

Since the calling script and the lambda URL are running on different domains, the web browser would require the right [CORS headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) (also called [CORS protocol](https://fetch.spec.whatwg.org/#http-cors-protocol)) to be present for the call to succeed.

The CORS protocol for the above `fetch()` involves sending an [HTTP OPTIONS request](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/OPTIONS) to the lambda with these three CORS headers to confirm that the lambda accepts requests from the script's domain:

```
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization
Origin: https://localhost:8080
```
The lambda is expected to respond with this set of headers:
```
Access-Control-Allow-Methods: GET
Access-Control-Allow-Headers: authorization
Access-Control-Allow-Origin: https://localhost:8080
```

### Option 1: Returning CORS from the lambda function's code

It is not hard to return a few headers from your lambda code. For example, these 4 lines of Rust code do the job:
```rust
    let mut headers = HeaderMap::new();
    headers.append("Access-Control-Allow-Origin", HeaderValue::from_static("https://localhost:8080"));
    headers.append("Access-Control-Allow-Methods", HeaderValue::from_static("GET"));
    headers.append("Access-Control-Allow-Headers",HeaderValue::from_static("authorization"));
```

On the other hand, it is an extra coding, testing and maintenance effort. Any changes to the CORS settings would require code changes as well.

If your client app sends one OPTIONS request for every GET/POST it doubles the number of invocations.
See the [Access-Control-Max-Age header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age) to reduce repeat OPTIONS calls by the same client.

Returning CORS from the lambda function's code may be a good option if you need extra control over handling the OPTIONS requests.

### Option 2: Configuring CORS headers in AWS Lambda settings

Function URLs can be configured to let AWS handle CORS preflight requests (HTTP OPTIONS method) and add necessary headers to all the other HTTP methods after your lambda returns its response.

This is a simpler and more reliable option that does not require any changes to the function's code.

![CORS config option checkbox](./lambda-url-cors-checkbox.png)


## Custom domain names for Lambda URLs

It is not possible to use custom domain names with Lambda URLs because the web server that invokes the lambda relies on the _Host_ HTTP header to identify which lambda to invoke, e.g. `host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws`.

__CNAME example__

- lambda URL: _mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws_
- CNAME record: `lambda.example.com CNAME mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws`
- _host_ header sent to AWS: `host: lambda.example.com`

The web server handling that request at the AWS end would not know which lambda function to invoke by looking at `host: lambda.example.com` and would return an error or time out.

Use _ApiGateway_ or _CloudFront_ as the proxy if using lambda Function URLs is not an option.


## Access control configuration for Lambda Function URL

Let's assume that our function is exposed to the internet and does not require AWS IAM authentication.

The following config allows public access to the function via its URL.

![Access control setting screenshot](./lambda-url-access-control.png)
![Access control policy screenshot](./lambda-url-rbac.png)

You need both the _Auth type: NONE_ setting and a resource-based policy statement to allow public access.
Having one or the other results in _403 Permission Denied_.

AWS automatically adds the required _FunctionURLAllowPublicAccess_ access policy when you choose _Auth type: NONE_ in the console.

## Request/response examples for different configuration options in detail

This section contains examples of HTTP headers exchanged between the web browser, AWS and the lambda function to help us understand how different configuration options affect the headers.

### Lambda URL request/response example without CORS protocol

1. Enable public access to your lambda function URL as explained earlier
2. Do not enable CORS settings
3. Send a request to the lambda URL displayed in the config screen


Your Function URL config should look similar to this:
![Basic lambda URL config screenshot](./lambda-url-config-basic.png)

A sample lambda URL call that does not require the CORS protocol
```javascript
const lambdaResponse = await fetch("https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/");
``` 

Your request may look similar to this example:

```
GET / HTTP/1.1
Host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/png,image/svg+xml,*/*;q=0.8
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
DNT: 1
Connection: keep-alive
Upgrade-Insecure-Requests: 1
Sec-Fetch-Dest: document
Sec-Fetch-Mode: navigate
Sec-Fetch-Site: same-origin
Sec-Fetch-User: ?1
Priority: u=4
Pragma: no-cache
Cache-Control: no-cache
```

The lambda function receives all the headers sent by the browser as part of the request payload and some additional AWS headers (see 6 headers starting with _x-_ at the end of the list).

```json
{
  "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/png,image/svg+xml,*/*;q=0.8",
  "accept-encoding": "gzip, deflate, br, zstd",
  "accept-language": "en-US,en;q=0.5",
  "authorization": "foo-bar",
  "cache-control": "no-cache",
  "dnt": "1",
  "host": "mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws",
  "pragma": "no-cache",
  "priority": "u=4",
  "sec-fetch-dest": "document",
  "sec-fetch-mode": "navigate",
  "sec-fetch-site": "same-origin",
  "sec-fetch-user": "?1",
  "upgrade-insecure-requests": "1",
  "user-agent": "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
  "x-amzn-tls-cipher-suite": "TLS_AES_128_GCM_SHA256",
  "x-amzn-tls-version": "TLSv1.3",
  "x-amzn-trace-id": "Root=1-66b44063-116ea8667f4b70e405b1b19a",
  "x-forwarded-for": "222.154.108.14",
  "x-forwarded-port": "443",
  "x-forwarded-proto": "https"
}
```
Function URL configuration with _CORS: not enabled_ option invokes the lambda for all HTTP methods, including OPTIONS and passes all browser headers to the lambda. 

Use this configuration if your lambda handles responses to the _HTTP OPTIONS_ method with the [CORS protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS).


### Example of a CORS request/response handled by lambda's code

This example has the same Lambda URL configuration as in the previous example:

![Basic lambda URL config screenshot](./lambda-url-config-basic.png)

This time we include an optional _Authorization_ header to trigger the CORS protocol:

```javascript
const lambdaResponse = await fetch("https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/",
  { headers: { Authorization: `Bearer ${token}` } },
);
``` 

The new request/response flow:
- a browser script running on https://localhost:8080 attempts to `fetch()` from the lambda's URL
- the browser initiates the CORS protocol by sending an HTTP OPTIONS request to the lambda
- the lambda replies with the necessary CORS headers
- the browser sends the GET request

The HTTP OPTIONS request would be very similar to the previous example with the addition of a few CORS headers:

- **origin**: https://localhost:8080
- **access-control-request-headers**: authorization
- **access-control-request-method**: GET

This OPTIONS request can be translated as the browser asking our lambda: can I send you a GET request with the _authorization_ header from a web page located at _https://localhost:8080_?

If the lambda replies _Yes_, the browser sends the GET request. If the lambda replies something other than _Yes_, the GET request is never sent and the script gets a CORS error.

Our lambda would see this list of headers for the above OPTIONS request (see last 3 lines):
```json
{
  "accept": "*/*",
  "accept-encoding": "gzip, deflate, br, zstd",
  "accept-language": "en-US,en;q=0.5",
  "cache-control": "no-cache",
  "dnt": "1",
  "host": "mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws",
  "pragma": "no-cache",
  "priority": "u=4",
  "sec-fetch-dest": "empty",
  "sec-fetch-mode": "cors",
  "sec-fetch-site": "cross-site",
  "user-agent": "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
  "x-amzn-tls-cipher-suite": "TLS_AES_128_GCM_SHA256",
  "x-amzn-tls-version": "TLSv1.3",
  "x-amzn-trace-id": "Root=1-66b42e1d-56f894f802ecd9bc345ef57a",
  "x-forwarded-for": "222.154.108.14",
  "x-forwarded-port": "443",
  "x-forwarded-proto": "https",
  "origin": "https://localhost:8080",
  "access-control-request-headers": "authorization",
  "access-control-request-method": "GET"
}
```

Assuming that our lambda function can handle CORS protocol and is happy with the request, the response would have the necessary CORS headers starting with _access-control-allow-_ to tell the browser that the lambda is happy to receive the GET request, as in this example (see last 4 lines):

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 18:18:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 5
Connection: keep-alive
x-amzn-RequestId: 9f50a878-597b-4fd9-8a07-717e078a2ab0
X-Amzn-Trace-Id: root=1-66b50c01-207a612c605445d738495a39;parent=5ff8d4e2feb9297b;sampled=0;lineage=a964c7ca:0
access-control-allow-origin: https://localhost:8080
access-control-allow-headers: authorization
access-control-allow-methods: GET
access-control-allow-credentials: true
```

The browser receives the above response and follows with HTTP GET asking the lambda to do some work, e.g. return some data.
The GET request contains the _Authorization_ header with a truncated JWT token (see the last line):

```
GET / HTTP/1.1
Host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
Origin: https://localhost:8080
DNT: 1
Connection: keep-alive
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: cross-site
Priority: u=0
Pragma: no-cache
Cache-Control: no-cache
Authorization: Bearer eyJhbGci...ba3mp4OQ
```

The lambda does its work and returns some payload with the following headers:

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 22:44:38 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 22
Connection: keep-alive
x-amzn-RequestId: 7307ef70-161c-431c-a7ac-b6ef4838549e
Vary: Origin
X-Amzn-Trace-Id: root=1-66b54a56-2822789c217e2f0847d6b03f;parent=0e288bd87a583781;sampled=0;lineage=a964c7ca:0
Access-Control-Allow-Origin: https://localhost:8080
Access-Control-Allow-Credentials: true
```

The above response has to contain `Access-Control-Allow-Origin: https://localhost:8080` and `Access-Control-Allow-Credentials: true` headers for the browser to accept it (last 2 lines).


### Example of CORS request/response handled by AWS

In this example, we added CORS to the Function URL configuration that says that the lambda is happy to receive HTTP GET/POST requests containing _Authorization_ and other headers from https://localhost:8080. It is also happy to receive some credentials.

![Lambda CORS config](./lambda-url-cors.png)

The client calls the lambda URL with the same _fetch()_ as before:
```javascript
const lambdaResponse = await fetch("https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/",
  { headers: { Authorization: `Bearer ${token}` } },
);
``` 

The browser does the same CORS protocol as before with the same CORS headers:

![Browser request sequence with OPTIONS/GET](./browser-request-options-get.png)

Unlike the previous example where the OPTIONS request was handled by the lambda code, no lambda invocation takes place for HTTP OPTIONS requests which are handled by AWS.

This response was generated by AWS and contains the settings configured in the CORS section of the Function URL:

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 18:53:07 GMT
Content-Type: application/json
Content-Length: 0
Connection: keep-alive
x-amzn-RequestId: 215426b9-920c-4d1f-b994-54ccd29b2612
Vary: Origin
Access-Control-Allow-Origin: https://localhost:8080
Access-Control-Allow-Headers: authorization,content-type,x-books-authorization
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Credentials: true
```

The last four lines of response tell the browser it may continue with more GET/POST requests.

Unlike the previous example, the lambda code was not involved in handling the CORS protocol - it was handled by AWS outside of the function's code.

As you can see, this is a much easier option than handling CORS inside the lambda code.


## A few "gotchas"

This section lists a few minor things that can suck up a lot of your time.

### Add one header per line in the CORS configuration form

Since the HTTP headers are sent as a comma-separated list it seems logical to enter the list in a single _Allow headers_ box (red highlight).
AWS will let you save the invalid config and produce an incorrect response to the OPTIONS request later.

Enter one header per line (green highlight). Remember that header names are case-insensitive.

![lambda headers - one per line example](./lambda-headers-one-per-line.png)

### Don't allow `localhost` CORS in production

It is not trivial to exploit this, but it is possible if the site has XSS vulnerabilities or a reverse proxy is involved.

See https://stackoverflow.com/questions/39042799/cors-localhost-as-allowed-origin-in-production for detailed explanations.

### Adding and deleting _FunctionURLAllowPublicAccess_ access policy

_FunctionURLAllowPublicAccess_ access policy is added by AWS when you choose _Auth type: NONE_ for the Function URL.

It is not removed if you change to _Auth type: AWS_IAM_, but the public access is no longer available. See [AWS docs](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html#urls-auth-none) for more details.

![Access control policy screenshot](./lambda-url-rbac.png)

Removing _FunctionURLAllowPublicAccess_ access policy while _Auth type: NONE_ blocks public access to the lambda's URL. 

### Header double-up

AWS adds `access-control-allow-origin` and `access-control-allow-credentials` CORS headers regardless of their presence in the response from the lambda. 

If our lambda returned CORS headers and the Function URL was configured to return CORS as well, the response would become invalid because `access-control-allow-origin` and `access-control-allow-credentials` would be included twice (see 4 last line):

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 18:53:09 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 22
Connection: keep-alive
Vary: Origin
x-amzn-RequestId: f1d1d6ce-1208-450d-8c61-e5a51f878090
X-Amzn-Trace-Id: root=1-66b51414-3998ea28145bd0d8661c065f;parent=7df2ad2039925c82;sampled=0;lineage=a964c7ca:0
access-control-allow-headers: x-books-authorization,authorization,content-type
access-control-allow-methods: GET, OPTIONS, POST
access-control-allow-origin: https://localhost:8080
access-control-allow-origin: https://localhost:8080
access-control-allow-credentials: true
access-control-allow-credentials: true
```

## References

- An awesome AWS Lambda debugging tool I used to experiment and capture requests and responses: [Github](https://github.com/rimutaka/lambda-debugger-runtime-emulator) / [Crates.io](https://crates.io/crates/lambda-debugger)
- AWS Lambda CORS docs: https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html?icmpid=docs_lambda_help#urls-cors
- CORS overview on MDN: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS
- CORS protocol spec: https://fetch.spec.whatwg.org/#http-cors-protocol
- CORS request headers
  - [Access-Control-Request-Method](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Request-Method)
  - [Access-Control-Request-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Request-Headers)
  - [Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Origin)
- Required CORS response headers
  - [Access-Control-Allow-Methods](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Allow-Methods)
  - [Access-Control-Allow-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Allow-Headers)
  - [Access-Control-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Allow-Origin)
- Optional CORS response headers
  - [Access-Control-Max-Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age)
  - [Access-Control-Expose-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Expose-Headers)
  - [Access-Control-Allow-Credentials](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Allow-Credentials)