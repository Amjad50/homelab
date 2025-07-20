{ ... }:

{
  services.fail2ban = {
    enable = true;

    # jails = {
    #   # Traefik access log monitoring for auth failures
    #   traefik-auth = {
    #     enabled = true;
    #     settings = {
    #       filter = "traefik-auth";
    #       logpath = "/var/log/traefik/access.log";
    #       skip_if_nologs = true;
    #       maxretry = 2;
    #       bantime = "24h";
    #       findtime = "10m";
    #       backend = "pyinotify";
    #     };
    #   };

    #   # Block bots searching for common attack paths
    #   traefik-botsearch = {
    #     enabled = true;
    #     settings = {
    #       filter = "traefik-botsearch";
    #       logpath = "/var/log/traefik/access.log";
    #       skip_if_nologs = true;
    #       maxretry = 10;
    #       bantime = "24h";
    #       findtime = "1m";
    #       backend = "pyinotify";
    #     };
    #   };
    # };
  };

  # Fail2ban custom filters
  # environment.etc = {
  #   "fail2ban/filter.d/traefik-auth.conf".text = ''
  #     [Definition]
  #     failregex = ^.*"ClientAddr":"<HOST>:.*"DownstreamStatus":(401|403).*$
  #     ignoreregex =
  #   '';

  #   "fail2ban/filter.d/traefik-botsearch.conf".text = ''
  #     [Definition]
  #     # fail regex based on traefik JSON access logs with enabled user agent logging
  #     failregex = ^{"ClientAddr":"<F-CLIENTADDR>.*</F-CLIENTADDR>","ClientHost":"<HOST>","ClientPort":"<F-CLIENTPORT>.*</F-CLIENTPORT>","ClientUsername":"<F-CLIENTUSERNAME>.*</F-CLIENTUSERNAME>","DownstreamContentSize":<F-DOWNSTREAMCONTENTSIZE>.*</F-DOWNSTREAMCONTENTSIZE>,"DownstreamStatus":<F-DOWNSTREAMSTATUS>(405|404|403|402|401)</F-DOWNSTREAMSTATUS>,"Duration":<F-DURATION>.*</F-DURATION>,"OriginContentSize":<F-ORIGINCONTENTSIZE>.*</F-ORIGINCONTENTSIZE>,"OriginDuration":<F-ORIGINDURATION>.*</F-ORIGINDURATION>,"OriginStatus":(0|405|404|403|402|401),"Overhead":<F-OVERHEAD>.*</F-OVERHEAD>,"RequestAddr":"<F-REQUESTADDR>.*</F-REQUESTADDR>","RequestContentSize":<F-REQUESTCONTENTSIZE>.*</F-REQUESTCONTENTSIZE>,"RequestCount":<F-REQUESTCOUNT>.*</F-REQUESTCOUNT>,"RequestHost":"<F-CONTAINER>.*</F-CONTAINER>","RequestMethod":"<F-REQUESTMETHOD>.*</F-REQUESTMETHOD>","RequestPath":"<F-REQUESTPATH>.*</F-REQUESTPATH>","RequestPort":"<F-REQUESTPORT>.*</F-REQUESTPORT>","RequestProtocol":"<F-REQUESTPROTOCOL>.*</F-REQUESTPROTOCOL>","RequestScheme":"<F-REQUESTSCHEME>.*</F-REQUESTSCHEME>","RetryAttempts":<F-RETRYATTEMPTS>.*</F-RETRYATTEMPTS>,.*"StartLocal":"<F-STARTLOCAL>.*</F-STARTLOCAL>","StartUTC":"<F-STARTUTC>.*</F-STARTUTC>","TLSCipher":"<F-TLSCIPHER>.*</F-TLSCIPHER>","TLSVersion":"<F-TLSVERSION>.*</F-TLSVERSION>","entryPointName":"<F-ENTRYPOINTNAME>.*</F-ENTRYPOINTNAME>","level":"<F-LEVEL>.*</F-LEVEL>","msg":"<F-MSG>.*</F-MSG>",("request_User-Agent":"<F-USERAGENT>.*</F-USERAGENT>",){0,1}?"time":"<F-TIME>.*</F-TIME>"}$

  #     datepattern = "StartLocal"\s*:\s*"%%Y-%%m-%%d[T]%%H:%%M:%%S\.%%f\d*(%%z)?",

  #     # ignore common errors like missing media files or JS/CSS/TXT/ICO stuff
  #     ignoreregex = ^{"ClientAddr":"<F-CLIENTADDR>.*</F-CLIENTADDR>","ClientHost":"<HOST>","ClientPort":"<F-CLIENTPORT>.*</F-CLIENTPORT>","ClientUsername":"<F-CLIENTUSERNAME>.*</F-CLIENTUSERNAME>","DownstreamContentSize":<F-DOWNSTREAMCONTENTSIZE>.*</F-DOWNSTREAMCONTENTSIZE>,"DownstreamStatus":<F-DOWNSTREAMSTATUS>(405|404|403|402|401)</F-DOWNSTREAMSTATUS>,"Duration":<F-DURATION>.*</F-DURATION>,"OriginContentSize":<F-ORIGINCONTENTSIZE>.*</F-ORIGINCONTENTSIZE>,"OriginDuration":<F-ORIGINDURATION>.*</F-ORIGINDURATION>,"OriginStatus":(0|405|404|403|402|401),"Overhead":<F-OVERHEAD>.*</F-OVERHEAD>,"RequestAddr":"<F-REQUESTADDR>.*</F-REQUESTADDR>","RequestContentSize":<F-REQUESTCONTENTSIZE>.*</F-REQUESTCONTENTSIZE>,"RequestCount":<F-REQUESTCOUNT>.*</F-REQUESTCOUNT>,"RequestHost":"<F-REQUESTHOST>.*</F-REQUESTHOST>","RequestMethod":"<F-REQUESTMETHOD>.*</F-REQUESTMETHOD>","RequestPath":"<F-REQUESTPATH>.*(\.png|\.txt|\.jpg|\.ico|\.js|\.css|\.ttf|\.woff|\.woff2)(/)*?</F-REQUESTPATH>","RequestPort":"<F-REQUESTPORT>.*</F-REQUESTPORT>","RequestProtocol":"<F-REQUESTPROTOCOL>.*</F-REQUESTPROTOCOL>","RequestScheme":"<F-REQUESTSCHEME>.*</F-REQUESTSCHEME>","RetryAttempts":<F-RETRYATTEMPTS>.*</F-RETRYATTEMPTS>,.*"StartLocal":"<F-STARTLOCAL>.*</F-STARTLOCAL>","StartUTC":"<F-STARTUTC>.*</F-STARTUTC>","TLSCipher":"<F-TLSCIPHER>.*</F-TLSCIPHER>","TLSVersion":"<F-TLSVERSION>.*</F-TLSVERSION>","entryPointName":"<F-ENTRYPOINTNAME>.*</F-ENTRYPOINTNAME>","level":"<F-LEVEL>.*</F-LEVEL>","msg":"<F-MSG>.*</F-MSG>",("request_User-Agent":"<F-USERAGENT>.*</F-USERAGENT>",){0,1}?"time":"<F-TIME>.*</F-TIME>"}$
  #   '';
  # };
}
