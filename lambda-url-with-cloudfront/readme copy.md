# AWS Lambda with CloudFront: caching, CORS and authorization by example

This post explores different configuration options for invoking AWS Lambda via a URL directly or with CloudFront.

About Lambda URLs: https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html

## Access control config

The following config allows public access to the function via its URL.

![Access control setting screenshot](./lambda-url-access-control.png)
![Access control policy screenshot](./lambda-url-rbac.png)

You need both _Auth type: NONE_ setting and a resource-based policy statement to allow public access.
Having one or the other results in _403 Permission Denied_.

_FunctionURLAllowPublicAccess_ access policy is added by AWS when you choose _Auth type: NONE_.
It is not removed if you change to _Auth type: AWS_IAM_, but the public access is no longer available.

## Basic Lambda URL config with no CORS

That lambda can be called via its URL from a web browser. In this example the URL was `https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws/` 

![Basic lambda URL config screenshot](./lambda-url-config-basic.png)


__Request headers sent by the browser__

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

The lambda received all the browser headers, including _Authorization_ and some additional AWS headers (6 headers starting with _x-_ at the end of the list):

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


## Custom domain for Lambda URL

It is not possible to make Lambda URL work with a custom domain because the web server that invokes the lambda relies on _Host_ header to identify which lambda to invoke, e.g. `host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws`.

Use ApiGateway or CloudFront as the proxy if using the lambda URL directly is not an option.


## Lambda function handles CORS protocol

This example has the same configuration as in the previous example.
The request comes from a different domain and requires CORS protocol:

- a browser script running on https://localhost:8080 attempts to invoke the lambda via its URL
- the browser initiates the CORS protocol by sending an HTTP OPTIONS request to the lambda
- the lambda replies with the necessary CORS headers
- the browser sends the GET request

### OPTIONS request

Headers of interest:
- **host**: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
- **origin**: https://localhost:8080
- **access-control-request-headers**: authorization,x-books-authorization
- **access-control-request-method**: GET

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

Lambda response with the necessary CORS headers:
```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 18:18:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 5
Connection: keep-alive
x-amzn-RequestId: 9f50a878-597b-4fd9-8a07-717e078a2ab0
access-control-allow-origin: https://localhost:8080
access-control-allow-headers: x-books-authorization,authorization,content-type
access-control-allow-methods: GET, OPTIONS, POST
X-Amzn-Trace-Id: root=1-66b50c01-207a612c605445d738495a39;parent=5ff8d4e2feb9297b;sampled=0;lineage=a964c7ca:0
access-control-allow-credentials: true
```

The above response allows the browser to proceed with the exchange.



## Lambda CORS configuration

In this example, we added CORS configuration to the same flow as before.

![Lambda CORS config](./lambda-url-cors.png)

This change prevents HTTPS OPTIONS requests from reaching the lambda and the browser gets the following response from the web server sitting in front of the lambda:

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

The response has everything the browser needs to continue with the exchange.

All request and response headers are passed through without interference.

### Header double-up

AWS adds `access-control-allow-origin` and `access-control-allow-credentials` CORS headers regardless of their presence in the response from the lambda. E.g. this is a valid response from a lambda that adds no CORS headers:
```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 20:29:53 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 22
Connection: keep-alive
x-amzn-RequestId: caaf612f-dbe8-4175-9531-bdad07b76da2
Access-Control-Allow-Origin: https://localhost:8080
Vary: Origin
X-Amzn-Trace-Id: root=1-66b52abf-7ddc7dd54973ec8851063810;parent=4ba9caf9403e972d;sampled=0;lineage=a964c7ca:0
Access-Control-Allow-Credentials: true
```
and if our lambda returns CORS headers the response becomes invalid because `access-control-allow-origin` and `access-control-allow-credentials` are included twice:

```
HTTP/1.1 200 OK
Date: Thu, 08 Aug 2024 18:53:09 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 22
Connection: keep-alive
x-amzn-RequestId: f1d1d6ce-1208-450d-8c61-e5a51f878090
access-control-allow-origin: *
access-control-allow-origin: https://localhost:8080
access-control-allow-headers: x-books-authorization,authorization,content-type
Vary: Origin
access-control-allow-methods: GET, OPTIONS, POST
X-Amzn-Trace-Id: root=1-66b51414-3998ea28145bd0d8661c065f;parent=7df2ad2039925c82;sampled=0;lineage=a964c7ca:0
access-control-allow-credentials: true
access-control-allow-credentials: true
```



AWS does not invoke the lambda for OPTIONS if CORS are configured.
Enter only one header per box. The entire CORS block is dropped with 200 if you write something like `auth0, content-type`
It does not add or replace any headers on other methods.

_Allow credentials_ option adds `Access-Control-Allow-Credentials: true` header.

All incoming headers are passed thru to the lambda.

Config
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

OPTIONS Request

```
OPTIONS / HTTP/1.1
Host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
Access-Control-Request-Method: GET
Access-Control-Request-Headers: auth0,authorization
Origin: https://localhost:8080
DNT: 1
Connection: keep-alive
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: cross-site
Priority: u=4
Pragma: no-cache
Cache-Control: no-cache
```

OPTIONS Response
```
HTTP/1.1 200 OK
Date: Wed, 07 Aug 2024 02:33:22 GMT
Content-Type: application/json
Content-Length: 0
Connection: keep-alive
x-amzn-RequestId: 4b11cd18-1a1d-420f-994a-046705304ce7
Access-Control-Allow-Origin: https://localhost:8080
Access-Control-Allow-Headers: auth0,content-type,authorization
Vary: Origin
Access-Control-Allow-Methods: GET,POST
```

GET Request

```
GET / HTTP/1.1
Host: mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
Authorization: Bearer eyJhbGciOiJkaXIiLCJlbmMiOiJBMjU2R0NNIiwiaXNzIjoiaHR0cHM6Ly9ib29rd29ybWZvb2QudXMuYXV0aDAuY29tLyJ9..EYTn14Eg8hnr6Vqx.lGhO2AXk7sptg1Xom6hraze-vuflg5whrl6XZ7wMxR_U_sJwsJwl0CAy6_kAVgDDtS9sZSwGilWNq9PGf9Hf2dLyvttRcSbyuq3lxQSXjRg-SJEMTqhq_ympvFTQRxCxOsnkHQuDgnwA5PYrrxKhPI3xovagbXa-_UcDEtMwhbIBg57rHOPG9tyeqT2zqh9BqMRb7CmNXS96AUSEz-461M2jqxpjeBjSjE6URfSuE6iWuOqG9pC8nt2TnDnz2qLwgRkA6DHdQkZhfuWhlf9LxMFHPzam-zp4oj4t65IxkVnESUPXCYmg76e6pxesRIY5nru_oGgOZQ.g0qxxG5YBiYLfBXGU90klw
Auth0: dummy-token
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

GET Response

```
HTTP/1.1 200 OK
Date: Wed, 07 Aug 2024 02:33:23 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 22
Connection: keep-alive
x-amzn-RequestId: b24031a2-8af2-401f-8982-5c449da35222
Access-Control-Allow-Origin: https://localhost:8080
Vary: Origin
X-Amzn-Trace-Id: root=1-66b2dcf2-1af0d74d4f99cb2274c8e85c;parent=6db7518affa713c7;sampled=0;lineage=a964c7ca:0
```

## CloudFront + Lambda

#### No policies config

The lambda is called on OPTIONS and GET. Some headers from Lambda CORS config are added on OPTIONS. Incoming headers are removed.

- CF cache: disabled
- CF req pol: none
- CF resp pol: none
- OPTIONS: access-control-allow-origin and access-control-allow-credentials are added by Lambda CORS on top of what was provided by the lambda resulting in the double-up, Access-Control-Allow-Methods and Access-Control-Allow-Headers are included from the lambda itself, if provided, otherwise none.
- GET: 
  - incoming headers are removed

#### All incoming headers policy

Origin request policy: 
```
Headers - All viewer headers
Cookies - All
Query strings - All
```

It does not call the lambda at all. Returns some CORS without explicit permission to do so:

```
access-control-allow-origin: *
access-control-allow-headers: auth0
access-control-allow-methods: GET
```


OPTIONS: returned by CF, no lambda invocation
Request:
```
OPTIONS /sync.html HTTP/2
Host: bookwormfood.com
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
Access-Control-Request-Method: GET
Access-Control-Request-Headers: auth0
Origin: https://localhost:8080
DNT: 1
Connection: keep-alive
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: cross-site
Priority: u=4
Pragma: no-cache
Cache-Control: no-cache
TE: trailers
```

Response from CF (no lambda)
```
HTTP/2 200 
content-length: 0
date: Wed, 07 Aug 2024 03:12:57 GMT
x-amzn-requestid: abad3bfd-537d-42e7-9678-9d821dc31a64
access-control-allow-origin: *
access-control-allow-headers: auth0
access-control-allow-methods: GET
access-control-expose-headers: x-amzn-RequestId,x-amzn-ErrorType,x-amzn-ErrorMessage,Date,x-amz-log-result,x-amz-function-error
access-control-max-age: 172800
x-cache: Miss from cloudfront
via: 1.1 d05901decd39bd339fbb13247b0f62f6.cloudfront.net (CloudFront)
x-amz-cf-pop: LAX3-C3
x-amz-cf-id: KEPU7sHCf8m0DAGjjR-2cusc9SBBpifphfyCX-qItK-brVDh8Ch8EA==
X-Firefox-Spdy: h2
```

GET: returns 403, no lambda invocation

Request
```
GET /sync.html HTTP/2
Host: bookwormfood.com
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate, br, zstd
Auth0: dummy-token
Origin: https://localhost:8080
DNT: 1
Connection: keep-alive
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: cross-site
Priority: u=0
Pragma: no-cache
Cache-Control: no-cache
TE: trailers
```

Response from CF, no lambda called
```
HTTP/2 403 
content-type: application/json
content-length: 16
date: Wed, 07 Aug 2024 03:12:57 GMT
x-amzn-requestid: dd4f3c31-0fe1-4fb3-8f69-5a13c1afff04
access-control-allow-origin: *
x-amzn-errortype: AccessDeniedException
access-control-expose-headers: x-amzn-RequestId,x-amzn-ErrorType,x-amzn-ErrorMessage,Date,x-amz-log-result,x-amz-function-error
x-cache: Error from cloudfront
via: 1.1 d05901decd39bd339fbb13247b0f62f6.cloudfront.net (CloudFront)
x-amz-cf-pop: LAX3-C3
x-amz-cf-id: vnBZ6opna8-dV_HMNfGXM80AtHR8lA0P5R9sGk6gGP6kf3GrvCoHPQ==
X-Firefox-Spdy: h2
```

#### All incoming headers CF policy + all response headers CF policy

The request policy is the same as before.
The response policy:

```
Access-Control-Allow-Credentials
false
Access-Control-Allow-Headers
*
Access-Control-Allow-Methods
ALL
Access-Control-Allow-Origin
https://localhost:8080
Access-Control-Expose-Headers
*
Access-Control-Max-Age (seconds)
600
```

Nothing changed. CF returns the same headers when not asked to do so.
It returns incorrect  Access-Control-Allow-Origin


#### All incoming headers CF policy + some response headers CF policy

The request policy is the same as before.
The response policy:

```
Access-Control-Allow-Credentials
false
Access-Control-Allow-Headers
auth0
content-type
authorization
Access-Control-Allow-Methods
GET
OPTIONS
Access-Control-Allow-Origin
https://localhost:8080
Access-Control-Expose-Headers
*
Access-Control-Max-Age (seconds)
600
```

Same as before.

Changing `Origin override` returns the right CORS in OPTIONS, but gives the same 403 for GET.


HOST header is the culprit.

Authorization header is removed.
See https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html#add-origin-custom-headers-forward-authorization
But, forwarding all headers forwards HOST and returns 403.

Can forward ALL and disable HOST as per https://www.reddit.com/r/aws/comments/1axx5c9/how_to_forward_authorization_header_using/


Max length of the header value:  	1,783 characters
All headers: 10,240 characters
See https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-limits.html#limits-custom-headers

Similar questions:

- https://stackoverflow.com/questions/78428354/aws-cors-configuration-with-lambda-function-url-and-a-cname-in-cloudfront-distri
- search for "cloudfront lambda cors"
- https://stackoverflow.com/questions/73360269/aws-cloudfront-on-lambda-function-via-the-function-url-url-returning-403-fobidde
