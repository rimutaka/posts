# AWS Lambda Function URL with CORS explained by example

This post explores different configuration options for invoking AWS Lambda via a URL directly or with CloudFront.

## Overview

### Why we need CORS

AWS Lambdas are normally [invoked](https://docs.aws.amazon.com/lambda/latest/dg/lambda-invocation.html) through a direct AWS API call or triggered by other AWS services.
Using [AWS Lambda URLs](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html) allows invoking them with a single unauthenticated HTTP call from a browser script, e.g.
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

The web browser requires the right [CORS headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) (also called [CORS protocol](https://fetch.spec.whatwg.org/#http-cors-protocol)) for that call to succeed. It would send an [HTTP OPTIONS request](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/OPTIONS) to the lambda with these three CORS headers:

```
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization
Origin: https://localhost:8080
```
and would proceed with HTTP GET if the lambda responded with:
```
Access-Control-Allow-Methods: GET
Access-Control-Allow-Headers: authorization
Access-Control-Allow-Origin: https://localhost:8080
```

There are two ways to return the correct CORS response:

- let the lambda handle the CORS and return the right headers in the response
- add CORS headers to the lambda function configuration

### Returning CORS from lambda function code

It is not complicated to return a few headers from your lambda code, but it is an extra coding, testing and maintenance effort. Any changes to the CORS settings would require code changes as well.

Handling CORS in the lambda can double the number of invocations. Use [Access-Control-Max-Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Max-Age) to reduce repeat calls by the same client.

### Configuring CORS headers in AWS Lambda settings

This is a simpler and more reliable option for most use cases to let AWS handle CORS preflight requests (HTTP OPTIONS) and add necessary headers to all the other HTTP methods.
It requires no changes to the function code.


## Custom domain names for Lambda URLs

It is not possible to make Lambda URL work with a custom domain because the web server that invokes the lambda relies on _Host_ header to identify which lambda to invoke, e.g. `host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws`.

__Example__

- lambda URL: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
- CNAME record: `lambda.example.com CNAME mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
- _host_ header sent to AWS: `host: lambda.example.com`

The web server handling that request at the AWS end would not know which lambda function to invoke and returns an error or times out.

Use ApiGateway or CloudFront as the proxy if using lambda URLa directly is not an option.


## Access control configuration for Lambda Function URL

Let's assume that the function is exposed to the internet and does not require AWS IAM authentication.

The following config allows public access to the function via its URL.

![Access control setting screenshot](./lambda-url-access-control.png)
![Access control policy screenshot](./lambda-url-rbac.png)

You need both _Auth type: NONE_ setting and a resource-based policy statement to allow public access.
Having one or the other results in _403 Permission Denied_.

The policy is added by AWS if you choose _NONE_ in the console.


## A basic Lambda URL request/response example, no CORS

1. Enable access to your lambda URL as explained above
2. Do not enable CORS settings
3. Send a request to the lambda URL displayed in the config screen, e.g. `https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/`

![Basic lambda URL config screenshot](./lambda-url-config-basic.png)

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
Authorization: foo-bar
```

Our request also includes _Authorization_ header because this header is often filtered out or dropped by middleware, especially CloudFront.

The lambda function received all the headers sent by the browser as part of the request payload and some additional AWS headers (6 headers starting with _x-_ at the end of the list).

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

This basic Lambda URL configuration allows passing all headers for all methods, including OPTIONS.
Use it if your lambda handles responses to _HTTP OPTIONS_ method with the [CORS protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS).



## Example of CORS request/response handled by function code

This example has the same Lambda URL configuration as in the previous example.

![Basic lambda URL config screenshot](./lambda-url-config-basic.png)

This time the request comes from a different domain and requires the CORS protocol to succeed:

- a browser script running on https://localhost:8080 attempts to invoke the lambda via its URL
- the browser initiates the CORS protocol by sending an HTTP OPTIONS request to the lambda
- the lambda replies with the necessary CORS headers
- the browser sends the GET request

Since the domain of the _Origin_ (where the script is running) and the _Host_ (lambda's domain name) are different, the browser initiates the CORS protocol by sending an HTTP OPTIONS request.

That OPTIONS request would be very similar to the previous example with the addition of a few CORS headers:

- **host**: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
- **origin**: https://localhost:8080
- **access-control-request-headers**: authorization
- **access-control-request-method**: GET

The browser is asking the server (our lambda): can I send you a GET request with _authorization_ header from a web page located at _https://localhost:8080_ ?

The full list of headers forwarded to the lambda:
```json
{
  "accept": "*/*",
  "accept-encoding": "gzip, deflate, br, zstd",
  "accept-language": "en-US,en;q=0.5",
  "access-control-request-headers": "authorization,x-books-authorization",
  "access-control-request-method": "GET",
  "cache-control": "no-cache",
  "dnt": "1",
  "host": "mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws",
  "origin": "https://localhost:8080",
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
  "x-forwarded-proto": "https"
}
```

Assuming that our lambda function can handle CORS protocol and is happy with the request, the response would have the necessary CORS headers.

The following response sample has the last four headers starting with _access-control-allow-_ to tell the browser that the lambda is happy to receive the GET request.

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

The browser follows with HTTP GET requesting the lambda to do some work, e.g. return some data.
This sample request contains _Authorization_ header with a truncated JWT token:

```
GET / HTTP/1.1
Host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
Authorization: Bearer eyJhbGci...ba3mp4OQ
Origin: https://localhost:8080
DNT: 1
Connection: keep-alive
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: cross-site
Priority: u=0
Pragma: no-cache
Cache-Control: no-cache
```

The lambda does its work and returns some payload with the following headers:

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 22:44:38 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 22
Connection: keep-alive
x-amzn-RequestId: 7307ef70-161c-431c-a7ac-b6ef4838549e
Access-Control-Allow-Origin: https://localhost:8080
Access-Control-Allow-Credentials: true
Vary: Origin
X-Amzn-Trace-Id: root=1-66b54a56-2822789c217e2f0847d6b03f;parent=0e288bd87a583781;sampled=0;lineage=a964c7ca:0
```

The response has to contain `Access-Control-Allow-Origin: https://localhost:8080` and `Access-Control-Allow-Credentials: true` headers for the browser to accept it.
Those headers have to be added by the lambda code, which is not hard, but why write that extra code when AWS can handle the CORS for us as shown in the following example?


## Example of CORS request/response handled by AWS outside of the lambda code

In this example, we added CORS to the Lambda Function URL configuration that says that the lambda is happy to receive HTTP GET/POST requests containing _Authorization_ and other headers from https://localhost:8080. It is also happy to receive some credentials.

![Lambda CORS config](./lambda-url-cors.png)

The client initiates the same _fetch()_ as before:
```javascript
const lambdaResponse = await fetch("https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/",
  { headers: { Authorization: `Bearer ${token}` } },
);
``` 

The browser does the same CORS protocol as before with exactly the same headers:

![Browser request sequence with OPTIONS/GET](./browser-request-options-get.png)

Unlike the previous example where the OPTIONS request was handled by the lambda code, no lambda invocation takes place for HTTP OPTIONS. It is handled by AWS and the response contains the settings configured in the CORS section of the Function URL:

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 18:53:07 GMT
Content-Type: application/json
Content-Length: 0
Connection: keep-alive
x-amzn-RequestId: 215426b9-920c-4d1f-b994-54ccd29b2612
Access-Control-Allow-Origin: https://localhost:8080
Access-Control-Allow-Headers: authorization,content-type,x-books-authorization
Vary: Origin
Access-Control-Allow-Methods: GET,POST
Access-Control-Allow-Credentials: true
```

The response has everything the browser needs to continue with the exchange as before.

Unlike the previous example, the lambda code did not need to know anything about the CORS protocol because it was handled outside of its code by AWS.

### Header double-up

AWS adds `access-control-allow-origin` and `access-control-allow-credentials` CORS headers regardless of their presence in the response from the lambda. E.g. this is a valid response from a lambda that adds no CORS headers.

If our lambda returned CORS headers the response would become invalid because `access-control-allow-origin` and `access-control-allow-credentials` would be included twice (see 4 last line):

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
access-control-allow-origin: *
access-control-allow-origin: https://localhost:8080
access-control-allow-credentials: true
access-control-allow-credentials: true
```

## A few "gotchas"

Beware of these minor things that can suck up a lot of your time.

### Add one header per line in the CORS configuration form

Since the HTTP headers are sent as a comma-separated list it seems logical to enter the list in the _Allow headers_ box.
AWS will let you save the invalid config and produce an incorrect response to OPTIONS request.

Enter one header per line.

![lambda headers - one per line example](./lambda-headers-one-per-line.png)

### Don't allow `localhost` CORS in production

It is not trivial to exploit this, but it is possible if the site has XSS or reverse proxy is involved.

See https://stackoverflow.com/questions/39042799/cors-localhost-as-allowed-origin-in-production for detailed explanations.

### Adding and deleting _FunctionURLAllowPublicAccess_ access policy

_FunctionURLAllowPublicAccess_ access policy is added by AWS when you choose _Auth type: NONE_ for the Function URL.

It is not removed if you change to _Auth type: AWS_IAM_, but the public access is no longer available.

Removing _FunctionURLAllowPublicAccess_ access policy while _Auth type: NONE_ blocks public access to the lambda's URL. 