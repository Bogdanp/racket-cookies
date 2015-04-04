#lang scribble/doc

@(require scribble/manual scribble/eval
          (for-label "common.rkt" "server.rkt" "user-agent.rkt"
                     racket/class
                     net/url net/head
                     web-server/http/request-structs))

@(define cookies-server-eval (make-base-eval))
@interaction-eval[#:eval cookies-server-eval
                         (require net/cookies/server)]

@title[#:tag "cookies"]{Cookies: HTTP State Management}

@author[(author+email "Jordan Johnson" "jmj@fellowhuman.com")]

This library provides utilities for handling cookies as specified
in RFC 6265 @cite["RFC6265"].

@defmodule[net/cookies]{
  Provides all names exported from @racketmodname[net/cookies/common],
  @racketmodname[net/cookies/server], and
  @racketmodname[net/cookies/user-agent].

  The @racketmodname[net/cookies/server] and
  @racketmodname[net/cookies/user-agent] are each designed to stand on
  their own, however, so for any program that is exclusively client- or
  server-side, it will suffice to import one of those two modules.
}

@; ------------------------------------------

@section[#:tag "cookies-common-procs"]{Cookies: Common Functionality}

@defmodule[net/cookies/common]{The @racketmodname[net/cookies/common] library
contains cookie-related code common to servers and user agents.
}

@defproc[(cookie-name? [v any/c]) boolean?]{
Returns @racket[#t] if @racket[v] is a valid cookie name (represented as
a string or a byte string), @racket[#f] otherwise.
 
Cookie names must consist of ASCII characters. They may not contain
control characters (ASCII codes 0-31 or 127) or the following ``separators'':
@itemlist[@item{double quotes}
          @item{whitespace characters}
          @item{@racket[#\@] or @racket[#\?]}
          @item{parentheses, brackets, or curly braces}
          @item{commas, colons, or semicolons}
          @item{equals, greater-than, or less-than signs}
          @item{slashes or backslashes}]
}

@defproc[(cookie-value? [v any/c]) boolean?]{
Returns @racket[#t] if @racket[v] is a valid cookie value (represented as
a string or byte string), @racket[#f] otherwise.
 
Cookie values must consist of ASCII characters. They may not contain:
@itemlist[@item{control characters}
          @item{whitespace characters}
          @item{double-quotes, except at the beginning and end if the entire
                value is double-quoted}
          @item{commas}
          @item{semicolons}
          @item{backslashes}]
}

@defproc[(path/extension-value? [v any/c])
         boolean?]{
Returns @racket[#t] iff @racket[v] is a string that can be used as the value
of a ``Path='' attribute, or as an additional attribute (or attribute/value
pair) whose meaning is not specified by RFC6265.
}

@defproc[(domain-value? [v any/c])
         boolean?]{
Returns @racket[#t] iff @racket[v] is a string that contains a (sub)domain
name, as defined by RFCs 1034 (Section 3.5) @cite["RFC1034"] and 1123
(Section 2.1) @cite["RFC1123"].
}

@; ------------------------------------------

@section[#:tag "cookies-server-procs"]{Cookies and HTTP Servers}

@defmodule[net/cookies/server]{The @racketmodname[net/cookies/server] library
is for handling cookies on the server end; it includes:
@itemlist[@item{a serializable @racket[cookie] structure definition}
           @item{functions to convert a cookie structure to a string, or
                 a value for the HTTP ``Set-Cookie'' response header}
           @item{functions that allow reading an HTTP ``Cookie'' header
                 generated by a user agent}]
}

@defstruct[cookie ([name       (and/c string? cookie-name?)]
                   [value      (and/c string? cookie-value?)]
                   [expires    (or/c date? #f)]
                   [max-age    (or/c (and/c integer? positive?) #f)]
                   [domain     (or/c domain-value? #f)]
                   [path       (or/c path/extension-value? #f)]
                   [secure?    boolean?]
                   [http-only? boolean?]
                   [extension  (or/c path/extension-value? #f)])
                  #:omit-constructor]{
  A structure type for cookies the server will send to the user agent. For
  client-side cookies, see @racketmodname[net/cookies/user-agent].
}

@defproc[(make-cookie [name cookie-name?]
                      [value cookie-value?]
                      [#:expires    exp-date (or/c date? #f) #f]
                      [#:max-age    max-age (or/c (and/c integer? positive?) #f)
                                    #f]
                      [#:domain     domain   (or/c domain-value? #f)         #f]
                      [#:path       path     (or/c path/extension-value? #f) #f]
                      [#:secure?    secure?  boolean? #f]
                      [#:http-only? http-only? boolean? #f]
                      [#:extension extension (or/c path/extension-value? #f)
                                   #f])
         cookie?]{
Constructs a cookie for sending to a user agent.

Both @racket[exp-date] and @racket[max-age] are for specifying a time at which
the user agent should remove the cookie from its cookie store.
@racket[exp-date] is for specifying this expiration time as a date;
@racket[max-age] is for specifying it as a number of seconds in the future.
If both @racket[exp-date] and @racket[max-age] are given, an RFC6265-compliant
user agent will disregard the @racket[exp-date] and use the @racket[max-age].

@racket[domain] indicates that the recipient should send the cookie back to
the server only if the hostname in the request URI is either @racket[domain]
itself, or a host within @racket[domain].

@racket[path] indicates that the recipient should send the cookie back to the
server only if @racket[path] is a prefix of the request URI's path.

@racket[secure], when @racket[#t], sets a flag telling the recipient that the
cookie may only be sent if the request URI's scheme specifies a ``secure''
protocol (presumably HTTPS).

@racket[http-only?], when @racket[#t], sets a flag telling the recipient that
the cookie may be communicated only to a server and only via HTTP or HTTPS.
@bold{This flag is important for security reasons:} Browsers provide JavaScript
access to cookies (for example, via @tt{document.cookie}), and consequently,
when cookies contain sensitive data such as user session info, malicious
JavaScript can compromise that data. The @tt{HttpOnly} cookie flag, set by
this keyword argument, instructs the browser not to make this cookie available
to JavaScript code.
@bold{If a cookie is intended to be confidential, both @racket[http-only?]
      and @racket[secure?] should be @racket[#t], and all connections should
      use HTTPS.}
(Some older browsers do not support this flag; see
@hyperlink["https://www.owasp.org/index.php/HttpOnly"]{the OWASP page on
HttpOnly} for more info.)
}

@defproc[(cookie->set-cookie-header [c cookie?]) bytes?]{
 Produces a byte string containing the value portion of a ``Set-Cookie:'' HTTP
 response header suitable for sending @racket[c] to a user agent.
 @examples[
 #:eval cookies-server-eval
 (cookie->set-cookie-header
  (make-cookie "rememberUser" "bob" #:path "/main"))
 ]
 This procedure uses @racket[string->bytes/utf-8] to convert the cookie to
 bytes; for an application that needs a different encoding function, use
 @racket[cookie->string] and perform the bytes conversion with that function.
}

@defproc[(clear-cookie-header [name cookie-name?]
                              [#:domain domain (or/c domain-value? #f) #f]
                              [#:path   path (or/c path/extension-value? #f) #f])
         bytes?]{
 Produces a byte string containing a ``Set-Cookie:'' header
 suitable for telling a user agent to clear the cookie with
 the given @racket[name]. (This is done, as per RFC6265, by
 sending a cookie with an expiration date in the past.)
 @examples[
 #:eval cookies-server-eval
 (clear-cookie-header "rememberUser" #:path "/main")
 ]

}

@defproc*[([(cookie-header->alist [header bytes?])
            (listof (cons/c bytes? bytes?))]
           [(cookie-header->alist [header bytes?]
                                  [decode (-> bytes? X)])
            (listof (cons/c X X))])]{
 Given the value part of a ``Cookie:'' header, produces an
 alist of all cookie name/value mappings in the header. If a
 @racket[decode] function is given, applies @racket[decode]
 to each key and each value before inserting the new
 key-value pair into the alist. Invalid cookies will not
 be present in the alist.

 If a key in the header has no value, then @racket[#""], or
 @racket[(decode #"")] if @racket[decode] is present, is
 used as the value.

 @examples[
 #:eval cookies-server-eval
 (cookie-header->alist #"SID=31d4d96e407aad42; lang=en-US")
 (cookie-header->alist #"SID=31d4d96e407aad42; lang=en-US"
                       bytes->string/utf-8)
 (cookie-header->alist #"seenIntro=; logins=3"
                       (compose (lambda (s) (or (string->number s) s))
                                bytes->string/utf-8))]

}

@defproc[(cookie->string [c cookie?])
         string?]{
  Produces a string containing the given cookie as text.

  @examples[#:eval cookies-server-eval
            (cookie->string
             (make-cookie "usesRacket" "true"))
            (cookie->string
             (make-cookie "favColor" "teal"
                          #:max-age 86400
                          #:domain "example.com"
                          #:secure? #t))]
}

@; ------------------------------------------

@section[#:tag "cookies-client-procs"]{Cookies and HTTP User Agents}

@(define cookies-ua-eval (make-base-eval))
@interaction-eval[#:eval cookies-ua-eval
                  (require net/cookies/user-agent)]


@defmodule[net/cookies/user-agent]{The
  @racketmodname[net/cookies/user-agent] library provides facilities
  specific to user agents' handling of cookies.

  Many user agents will need only two of this library's functions:
  @itemlist[@item{@racket[extract-and-save-cookies!], for storing cookies}
            @item{@racket[cookie-header], for retrieving them and
                  generating a ``Cookie:'' header}]
}

@defstruct[ua-cookie ([name            cookie-name?]
                      [value           cookie-value?]
                      [domain          domain-value?]
                      [path            path/extension-value?]
                      [expiration-time (and/c integer? positive?)]
                      [creation-time   (and/c integer? positive?)]
                      [access-time     (and/c integer? positive?)]
                      [persistent?     boolean?]
                      [host-only?      boolean?]
                      [secure-only?    boolean?]
                      [http-only?      boolean?])
           #:omit-constructor]{
 A structure representing a cookie from a user agent's
 point of view.

 All times are represented as the number of seconds since
 midnight UTC, January 1, 1970, like the values produced by
 @racket[current-seconds].

 It's unlikely a client will need to construct a @racket[ua-cookie]
 instance directly (except perhaps for testing); @racket[extract-cookies]
 produces struct instances for all the cookies received in a server's response.
}

@defproc[(cookie-expired? [cookie ua-cookie?]
                          [current-time integer? (current-seconds)])
         boolean?]{
  True iff the given cookie's expiration time precedes @racket[current-time].
}

@;----------------------------------------

@subsection[#:tag "cookies-client-jar"]{Cookie jars: Client storage}

@defproc[(extract-and-save-cookies!
           [headers (listof (or/c header? (cons/c bytes? bytes?)))]
           [url url?]
           [decode (-> bytes? string?) bytes->string/utf-8])
         void?]{
  Reads all cookies from any ``Set-Cookie'' headers present in
  @racket[headers] received in an HTTP response from @racket[url],
  converts them to strings using @racket[decode], and stores them
  in the @racket[current-cookie-jar].

  @examples[#:eval cookies-ua-eval
            (require net/url)
            (define site-url
              (string->url "http://test.example.com/apps/main"))
            (extract-and-save-cookies!
             '((#"X-Test-Header" . #"isThisACookie=no")
               (#"Set-Cookie" . #"a=b; Max-Age=2000; Path=/")
               (#"Set-Cookie" . #"user=bob; Max-Age=86400; Path=/apps"))
             site-url)
            (cookie-header site-url)]
}

@defproc[(save-cookie! [c ua-cookie?] [via-http? boolean? #t]) void?]{
  Attempts to save a single cookie @racket[c], received via an HTTP API iff
  @racket[via-http?], to the @racket[current-cookie-jar]. Per Section 5.3
  of RFC 6265, the cookie will be ignored if its @racket[http-only?] flag
  (or that of the cookie it would replace) is set and it wasn't received via
  an HTTP API.
}

@defproc[(cookie-header [url url?]
                        [encode (-> string? bytes?) string->bytes/utf-8]
                        [#:filter-with ok? (-> ua-cookie? boolean?)
                         (lambda (x) #t)])
         (or/c bytes? #f)]{
  Finds any unexpired cookies matching @racket[url] in the
  @racket[current-cookie-jar], removes any for which @racket[ok?] produces
  @racket[#f], and produces the value portion of a ``Cookie:'' HTTP request
  header. Produces @racket[#f] if no cookies match.
  
  Cookies with the ``Secure'' flag will be included in this header iff
  @racket[(url-scheme url)] is @racket["https"], unless you remove them
  manually using the @racket[ok?] parameter.

  @examples[#:eval cookies-ua-eval
            (cookie-header
             (string->url "http://test.example.com/home"))]
}

@definterface[cookie-jar<%> ()]{
  An interface for storing cookies received from servers. Implemented by
  @racket[list-cookie-jar%]. Provides for saving cookies (imperatively)
  and extracting all cookies that match a given URL.

  Most clients will not need to deal with this interface, and none should
  need to call its methods directly. (Use @racket[cookie-header] and
  @racket[extract-and-save-cookies!], instead.) It is provided for situations
  in which the default @racket[list-cookie-jar%] class will not suffice. For
  example, if the user agent will be storing thousands of cookies, the linear
  insertion time of @racket[list-cookie-jar%] could mean that writing a
  @racket[cookie-jar<%>] implementation based on hash tables, trees, or a DBMS
  might be a better alternative.

  Programs requiring such a class should install an instance
  of it using the @racket[current-cookie-jar] parameter.

  @defmethod[(save-cookie! [c ua-cookie?] [via-http? boolean? #t]) void?]{
    Saves @racket[c] to the jar, and removes any expired cookies from
    the jar as well.
    
    @racket[via-http?] should be @racket[#t] if the cookie
    was received via an HTTP API; it is for properly ignoring the cookie if
    the cookie's @racket[http-only?] flag is set, or if the cookie is
    attempting to replace an ``HTTP only'' cookie already present in the jar.
  }

  @defmethod[(save-cookies! [cs (listof ua-cookie?)] [via-http? boolean? #t])
             void?]{
    Saves each cookie in @racket[cs] to the jar, and removes any expired
    cookies from the jar. See the note immediately above, for explanation of the
    @racket[via-http?] flag.
  }

  @defmethod[(cookies-matching [url url?]
                               [secure? boolean?
                                        (equal? (url-scheme url) "https")])
             (listof ua-cookie?)]{
    Produces all cookies in the jar that should be sent in the
    ``Cookie'' header for a request made to @racket[url]. @racket[secure?]
    specifies whether the cookies will be sent via a secure protocol.
    (If not, cookies with the ``Secure'' flag set should not be returned by
    this method.)
    
    This method should produce its cookies in the order expected according to
    RFC6265:
    @itemlist[
      @item{Cookies with longer paths are listed before cookies with shorter
            paths.}
      @item{Among cookies that have equal-length path fields, cookies with
            earlier creation-times are listed before cookies with later
            creation-times.}]
    If there are multiple cookies in the jar with the same name and different
    domains or paths, the RFC does not specify which to send. The default
    @racket[list-cookie-jar%] class's implementation of this method produces
    @bold{all} cookies that match the domain and path of the given URL, in the
    order specified above.
  }
}

@defclass[list-cookie-jar% object% (cookie-jar<%>)]{
  Stores cookies in a list, internally maintaining a sorted order that
  mirrors the sort order specified by the RFC for the ``Cookie'' header.
}

@defparam[current-cookie-jar jar (is-a?/c cookie-jar<%>)
                             #:value (new list-cookie-jar%)]{
  A parameter that specifies the cookie jar to use for storing and
  retrieving cookies.
}

@; ----------------------------------------

@subsection[#:tag "cookies-client-parsing"]{Reading the Set-Cookie header}

@defproc[(extract-cookies [headers (listof (or/c header? (cons/c bytes? bytes?)))]
                          [url url?]
                          [decode (-> bytes? string?)
                                  bytes->string/utf-8])
         (listof ua-cookie?)]{
 Given a list of all the headers received in the response to
 a request from the given @racket[url], produces a list of
 cookies corresponding to all the ``Set-Cookie'' headers
 present. The @racket[decode] function is used to convert the cookie's
 textual fields to strings.

 This function is suitable for use with the @racket[headers/raw]
 field of a @racket[request] structure (from
 @racketmodname[web-server/http/request-structs]), or with the output of
 @racket[(extract-all-fields h)], where @racket[h] is a byte string.
}

@defproc[(parse-cookie [set-cookie-bytes bytes?]
                       [url url?]
                       [decode (-> bytes? string?) bytes->string/utf-8])
         ua-cookie?]{
 Given a single ``Set-Cookie'' header's value 
 @racket[set-cookie-bytes] received in response to a request
 from the given @racket[url], produces a @racket[ua-cookie]
 representing the cookie received.

 The @racket[decode] function is used to convert the cookie's
 textual fields (@racket[name], @racket[value], @racket[domain],
 and @racket[path]) to strings.
}

@defproc[(default-path [url url?]) string?]{
 Given a URL, produces the path that should be used for a
 cookie that has no ``Path'' attribute, as specified in
 Section 5.1.4 of the RFC.
}

@deftogether[(@defthing[max-cookie-seconds (and/c integer? positive?)]
              @defthing[min-cookie-seconds (and/c integer? negative?)])]{
 The largest and smallest integers that this user agent library will
 use, or be guaranteed to accept, as time measurements in seconds since
 midnight UTC on January 1, 1970.
}

@defproc[(parse-date [s string?]) (or/c string? #f)]{
 Parses the given string for a date, producing @racket[#f] if
 it is not possible to extract a date from the string using
 the algorithm specified in Section 5.1.1 of the RFC.
}

@; ------------------------------------------

@section[#:tag "cookies-acknowledgments"]{Acknowledgements}

The server-side library is based on the original
@racketmodname[net/cookie] library by
@author+email["Francisco Solsona" "solsona@acm.org"]. Many of the
cookie-construction tests for this library are adapted from the
@racketmodname[net/cookie] tests.

@author+email["Roman Klochkov" "kalimehtar@mail.ru"] wrote the first
client-side cookie library on which this user-agent library is based.
In particular, this library relies on his code for parsing dates and
other cookie components.

@; ------------------------------------------

@(bibliography
  (bib-entry #:key "RFC1034"
             #:title "Domain Names - Concepts and Facilities"
             #:author "P. Mockapetris"
             #:location "RFC"
             #:url "http://tools.ietf.org/html/rfc1034.html"
             #:date "1987")
  
  (bib-entry #:key "RFC1123"
             #:title "Requirements for Internet Hosts - Application and Support"
             #:author "R. Braden (editor)"
             #:location "RFC"
             #:url "http://tools.ietf.org/html/rfc1123.html"
             #:date "1989")
  
  (bib-entry #:key "RFC6265"
             #:title "HTTP State Management Mechanism"
             #:author "A. Barth"
             #:location "RFC"
             #:url "http://tools.ietf.org/html/rfc6265.html"
             #:date "2011")
  )
