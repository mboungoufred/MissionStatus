public class ContactSyncService {

    private static final String API_URL    = 'https://fxyozmgb2xs5iogcheotxi6hoa0jdhiz.lambda-url.eu-central-1.on.aws';
    private static final String AUTH_TOKEN = 'salesforceAuthToken';

    public class ContactPayload {
        public String  id;
        public Boolean is_active;

        public ContactPayload(String contactId, Boolean isActive) {
            this.id        = contactId;
            this.is_active = isActive;
        }
    }

    // @future is required: callouts cannot be made in the same transaction as DML
    @future(callout=true)
    public static void syncContacts(String payloadJson) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(API_URL);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', AUTH_TOKEN);
        req.setBody(payloadJson);
        System.debug('payloadJson = ' + payloadJson);

        HttpResponse res = new Http().send(req);

        switch on res.getStatusCode() {
            when 200 {
                System.debug(LoggingLevel.INFO, 'ContactSyncService: sync successful.');
            }
            when 401 {
                // AUTH_TOKEN is missing or wrong — must be fixed in code, no point retrying
                System.debug(LoggingLevel.ERROR,
                    'ContactSyncService [401] Bad authorization: check the Authorization header value.');
            }
            when 400 {
                // Payload structure is invalid — log it so the bad JSON can be inspected
                System.debug(LoggingLevel.ERROR,
                    'ContactSyncService [400] Bad request: payload must be an array of {id: string, is_active: boolean}. Payload sent: ' + payloadJson);
            }
            when 404 {
                // Wrong HTTP method or endpoint — configuration issue
                System.debug(LoggingLevel.ERROR,
                    'ContactSyncService [404] Not found: verify the endpoint URL and that the method is PATCH.');
            }
            when else {
                System.debug(LoggingLevel.ERROR,
                    'ContactSyncService [' + res.getStatusCode() + '] Unexpected response: ' + res.getBody());
            }
        }
    }
}
