# AWS Lambda with CloudFront configuration options explained

This post explores different configuration options for invoking AWS Lambda via CloudFront to help you understand how different CloudFront and Lambda Function URL settings affect CORS and Authorization headers.

## Overview

AWS Lambda Functions can be invoked via a public [AWS Lambda Function URL](https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html) with an HTTP call from a browser script, e.g.

```javascript
const lambdaResponse = await fetch(
  "https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws",
  {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  },
);
``` 

There are two possible downsides to that type of invocation:

1. you cannot use a custom domain - it has to be an AWS-generated URL like `https://mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws`
2. There is no server-side caching (higher cost, slower response time, etc)

Calling your lambdas via CloudFront solves both of those issues.

### Special considerations

There is quite a bit of configuration to be done upfront to make a Lambda function work with CloudFront:

- Lambda Function URL (access control, CORS)
- CloudFront origin
- CloudFront behaviors
- CloudFront caching policy
- CloudFront origin request policy
- CloudFront response policy

This guide complements the [official AWS documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html#concept_lambda_function_url) with examples and shortcuts.

About Lambda URLs: https://docs.aws.amazon.com/lambda/latest/dg/urls-configuration.html

## Core concepts

This section CloudFront terms and concepts that affect Lambda, CORS and Authorization headers.

**General**
- CloudFront forwards all requests to the Lambda URL, including OPTIONS
- CloudFront can cache OPTIONS responses
- CloudFront can drop or overwrite some of the headers it received from either the client app or the lambda function
- _Authorization_, _Host_ and other headers are used by AWS in communication between CloudFront and Lambda and may conflict with the same headers used by the web client

**CORS headers** can be added in three places. Choose one that is most suitable for your use case:
- by the code inside the lambda function
- by AWS if Lambda Function URL CORS were configured
- by CloudFront via _Response Headers Policy_ (most flexible)

**Origin access control** Lambda Origin setting tells CloudFront if it should sign requests sent to the Lambda Function URL.
Signing requests takes over _Authorization_ header so that you cannot forward it from the client app to the lambda.

**Caching policy** of a Behavior tells CloudFront which headers to use as caching keys.
- headers included in the caching key are passed onto the lambda
- you have to include your authorization key to avoid serving one user's response to another user
- even if you include the _Authorization_ header in the key it may be overtaken by the AWS signature configured in _Origin access control_
- you do not have to have a caching policy for the CORS to work
- AWS recommends _CachingDisabled_ for Lambda URLs

**Origin request policy** tells CloudFront which headers to forward to the lambda.
- you should not forward the _Host_ header (it returns an error at runtime if you do)
- CloudFront may drop or replace some headers
- _AllViewerExceptHostHeader_ policy works fine with CORS and is the default choice for Lambda URLs
- you can choose _None_ if you don't need to pass any authorization headers and generate the CORS response inside CloudFront

**Response headers policy** tells CloudFront what headers to add to the response. It can add or overwrite CORS headers after the lambda function.
- you can choose _None_ if the lambda function handles the CORS response
- you can choose a suitable managed CORS policy from the list to complement or overwrite the lambda's response
- you can create your own policy to complement or overwrite the lambda's response

**Header quotas** set [limits](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-limits.html#limits-custom-headers) to how much data you can put into custom headers.
- Max length of a header value: 1,783 characters
- Max length of all headers: 10,240 characters


## Lambda Function URL configuration for CloudFront

Let's assume that you already have a working Lambda function with a configured URL for public access and we need to make it work with CloudFront.

## Lambda URL access control config

The following config lets CloudFront access a Lambda function via its URL.

![Access control setting screenshot](./cf-lambda-url-access-control.png)

We will add the CloudFront IAM policy to the Lambda at a later stage.



Setting your function URL access control to _Auth type: NONE_ will allow CloudFront access, but will also make it public.

## Lambda URL CORS headers

Enabling CORS headers in Lambda Function URL settings will intercept HTTP OPTIONS requests sent to the function and return the configured response.

Disabling CORS forwards HTTP OPTIONS requests to the function handler.

The same CORS headers can be configured inside CloudFront with more flexibility.

CloudFront can cache HTTP OPTIONS responses regardless of which of the above strategies of handling CORS you choose.


## CloudFront configuration

A Lambda function becomes an origin in a CloudFront distribution.

You need to configure _Origins_, _Behaviors_ and _Policies_ to make it work. There should be no changes to the general _Distribution_ settings, security or error pages.

In this example _client-sync lambda_ origin is linked to _/sync.html_ path, so if a client app makes a `fetch()` call to `https://d9tskged4za87.cloudfront.net/sync.html` the request will be forwarded to _client-sync lambda_ for processing.

![CloudFront Origins](./cf-origins.png)

![CloudFront Behaviors](./cf-behaviors.png)

### Origin configuration

The origin in this case is our lambda function.

- **origin domain:** copy-paste the domain of the Lambda Function URL, e.g. `mq75dt64puwxk3u6gjw2rhak4m0bcmmi.lambda-url.us-east-1.on.aws`
- **origin path:** leave blank
- **name:** give it an informative name, spaces are OK; it will not be used as an ID
- **origin access control:** create a new policy that can be shared between multiple lambda functions

#### Origin access control and Authorization header

The origin access control settings affect the use of _Authorization_ header. This can be a sticking point because signing CloudFront requests to the lambda function URL also uses the same _Authorization_ header.

![Origin Access Control](./cf-origin-access-control.png)

__Do not sign requests__
- _Authorization_ header from the browser can be passed to the lambda
- the lambda must have _Auth type: NONE_ and a public access policy enabled

__Sign requests__
- _Authorization_ header is used for CloudFront signatures
- the lambda code does not get the _Authorization_ header at all
- _Authorization_ header from the browser is dropped
- the lambda can have _Auth type: AWS_IAM_ and no public access

__Do not override Authorization header__
This is a combination of the two previous policies:
- sign if there is no _Authorization_ header coming from the browser
- do not sign if there is one coming from the browser
- the lambda must have _Auth type: NONE_ and a public access policy enabled

The _Origin Access_ policy can be edited later from the sidebar under _Security / Origin access_ menu.

#### Lambda access policy

Copy-paste and run the `aws lambda add-permission` command displayed after you create the _Origin access policy_:

![Lambda access policy](./cf-custom-access-policy.png)

If you go back to your lambda function, you should see the newly added policy:

![Access control policy screenshot](./cf-lambda-url-rbac.png)

and its contents with your account and distribution IDs:

![Access control policy contents](./cf-lambda-url-rbac-contents.png)


### Behavior configuration

Create a new _behavior_ with the path to the endpoint that invokes the Lambda (1) and the name of origin you created for the lambda earlier (2). In our case, the names are:

![Cloudfront behavior settings](./cf-create-behavior.png)

Further down the form, choose the allowed methods. You have to select an option with the _HTTP OPTIONS_ method for CORS to work.

Select the additional OPTIONS caching if you want to avoid sending repeat OPTIONS requests to the origin.  
CloudFront cache OPTIONS if this box is checked and a caching policy is enabled.  
Selecting _CachingDisabled_ policy disables OPTIONS caching even if this box is checked.

![Allowed HTTP methods screen](./cf-behavior-options-cache.png)

In the policies section of the form select:

- Cache policy _CachingDisabled_
- Origin request policy _AllViewerExceptHostHeader_
- Response headers policy: 
  - select None if the Lambda Function URL CORS option was configured, or
  - create a new policy (more on this is further in the document), select None for now anyway

Save this intermediate configuration for a test. The policy details and how they relate to CORS are explained further in this guide.

## CloudFront policies and CORS headers

### Caching policy

#### Caching disabled

AWS recommends disabling caching for Lambda functions because most of the requests are unique and should not be cached. See https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html#managed-cache-policy-caching-disabled

![Caching policy disabled selection](./cf-caching-policy-disabled.png)

Some headers, including the _Authorization_ header, are [removed by CloudFront if caching is disabled](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html#request-custom-headers-behavior).

#### Caching enabled + Authorization header

_Authorization_ header gets [special treatment](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html#RequestCustomClientAuth) from AWS:

- CloudFront does not pass it to lambda functions for GET/HEAD requests unless it is included in the caching policy
- CloudFront forwards it for DELETE, PATCH, POST, and PUT requests

The above statements are negated by a different setting:
- AWS uses _Authorization_ header for IAM authentication, so even if you have _Auth type: AWS_IAM_ in the Function URL settings the _Authorization_ header will not reach the lambda no matter what the caching policy says

Workaround for passing _Authorization_ header to lambdas:
- disable Lambda Function URL IAM authentication with _Auth type: NONE_
- add _Authorization_ header to the caching policy

If disabling Lambda Function URL IAM authentication is not an option:
- keep _Auth type: AWS_IAM_ in the Function URL settings
- use a custom header to pass the authentication value from your web client to your lambda, e.g. `x-myapp-auth: Bearer some-long-JWT-value`
- add the custom header to the caching policy to prevent responses to one authenticated user served to someone else

## Origin request policy

Use [AllViewerExceptHostHeader](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-except-host-header) or create a custom one that excludes the _Host_ header from being forwarded to lambda.

![Origin request policy](./cf-origin-request-policy.png)

The name of that origin request policy is quite misleading because CloudFront removes and repurposes some of the headers, e.g. _Authorization_ and [many others](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html#request-custom-headers-behavior).


## Response headers policy

Use this policy only if you want CloudFront to add CORS and other headers to the response on top or instead of what your lambda returned in its response. For example, this policy adds all the necessary CORS headers to let scripts running in your local DEV environment (https://localhost:8080) call the lambda function:

![sample response policy](./cf-response-policy-with-cors.png)

You can use one of the [AWS-managed CORS policies](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-response-headers-policies.html) to allow scripts from any domain to access your lambda function (`Access-Control-Allow-Origin: *`). 

## References

- AWS Lambda debugging tool I used to experiment and capture requests and responses: [Github](https://github.com/rimutaka/lambda-debugger-runtime-emulator)
- Lambda URL access control: https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html#urls-auth-iam
- Cache policy: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cache-key-understand-cache-policy.html#cache-policy-headers
- Request and response behavior for custom origins: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html
- Configure CloudFront to forward the Authorization header: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html#add-origin-custom-headers-forward-authorization
- How origin request policies and cache policies work together: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-how-origin-request-policies-and-cache-policies-work-together.html
- 
- 

- Helpful answers: 
  - https://serverfault.com/questions/1053906/how-to-whitelist-authorization-header-in-cloudfront-custom-origin-request-policy
  - https://www.reddit.com/r/aws/comments/1axx5c9/how_to_forward_authorization_header_using/


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
