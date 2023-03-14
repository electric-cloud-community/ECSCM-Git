import groovy.json.JsonSlurper
import groovy.json.JsonOutput

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.security.InvalidKeyException


def rawPayload = new String(args.payload)
def rawHeaders = args.headers
def url = args.url



// User-Agent: Bitbucket-Webhooks/2.0
// User-Agent: GitHub-Hookshot/2c922d2


Map lowercaseHeaders = [:]
rawHeaders.each {k, v ->
    lowercaseHeaders[k.toLowerCase()] = v
}

def userAgent = lowercaseHeaders['user-agent']


def eventData = [:]
def schedulesSearchParameters = [:]

if (userAgent =~ /Bitbucket-Webhooks/) {
    // it is bitbucket

     def  rawEventType = lowercaseHeaders['x-event-key']
     if (!(rawEventType in ['repo:push'])) {
        return response(400, "Only push event can be processed right now: event is ${rawEventType} (Bitbucket)")
    }

    def payload = new JsonSlurper().parseText(rawPayload)
    if (!(payload instanceof Map)) {
        return response(400, "Can't parse payload, Expected JSON object. (Bitbucket)")
    }

    def push = payload['push']
    if (!push) {
        return response(400, "Only push event can be processed right now, no push field in the payload (Bitbucket)")
    }
    def actor = payload['actor']
    def repository = payload['repository']

    def scm = repository.get('scm')
    def repositoryName = repository.get('full_name')

    //  split raw eventType to prefix and action
    def (eventPrefix, eventType) = rawEventType.split(":", 2)
    def branch = null

    if (push.changes?.size() != 1) {
        throw new RuntimeException("Wrong changes size: " + push.changes?.size())
    }

    push.changes.each { change ->
        def n = change['new']
        if (!n) {
                return response(400, "Missing new changes. Looks like this is a branch deletion and it is not supported right now (Bitbucket)")
        }
        if (n.type == 'branch') {
            branch = n.name
            eventData.headCommitId = n.target?.hash
            eventData.url = n.target.links?.self?.href
            eventData.authorUsername = n.target.author?.user?.nickname
            eventData.authorName = n.target.author?.user?.display_name
            eventData.branch = branch
            eventData.message = n.target?.message
            eventData.commits = change?.commits
            eventData.head = n.target
        }
    }

    if (!branch) {
        return response(400, "Can't find branch in changes. (Bitbucket)")
    }

    schedulesSearchParameters = [
        ec_webhookRepositoryName: repositoryName,
        ec_webhookEventType: eventType,
        ec_webhookEventSource: 'bitbucket',
        ec_webhookBranch: branch
    ]
}
else {
    // it is github

    def signature = lowercaseHeaders['x-hub-signature']
    def eventType = lowercaseHeaders['x-github-event']

    if (!(eventType in ['push', 'ping'])) {
        return response(400, "Only push and ping events can be processed right now: event is ${eventType} (Github)")
    }

    // Parameters
    if (!rawPayload) {
        return response(400, "No payload was found in the request (Github)")
    }

    if (!rawHeaders) {
        return response(400, "No headers were found in the request (Github)")
    }

    if (signature) {
        def config = args.config
        if (!config) {
            return response(403, "No configuration is provided, but the signature exists. Please provide the name of the valid configuration containing secret for the payload validation.")
        }
        def credentials = config.credential

        def cred = credentials.find {
            it.credentialName.endsWith('webhookSecret')
        }
        secret = cred.password
        if (!secret) {
            return response(403, "No secret is defined in the plugin configuration")
        }
        def calculatedSignature = 'sha1=' + hmacSha1(secret, rawPayload)
        if (calculatedSignature != signature)
            return response(403, "Signatures do not match".toString())
    }

    if (eventType == 'ping') {
        return [code: 200, payload: "The ping was successfull", headers: ['content-type': 'text/plain']]
    }

    def payload = new JsonSlurper().parseText(rawPayload)
    def repositoryName = payload.repository.full_name

    def branch = payload.ref.replaceAll('refs/heads/', '')
    eventData = [
        headCommitId: payload.head_commit.id,
        authorUsername: payload.head_commit.author.username,
        authorName: payload.head_commit.author.name,
        message: payload.head_commit.message,
        url: payload.head_commit.url,
        commits: payload.commits,
        head: payload.head_commit,
        branch: branch
    ]

    schedulesSearchParameters = [
        ec_webhookRepositoryName: repositoryName,
        ec_webhookEventType: eventType,
        ec_webhookEventSource: 'github',
        ec_webhookBranch: branch
    ]
}


def json = JsonOutput.toJson(schedulesSearchParameters)

def result
try {
    result = runProcedure(
        projectName: '/plugins/ECSCM/project',
        procedureName: 'ProcessWebHookSchedules',
        actualParameter: [
            ec_webhookData: JsonOutput.toJson(eventData),
            ec_webhookSchedulesSearchParams: json,
        ]
    )
} catch (Throwable e) {
    return response(500, "The procedure failed to start: ${e.message}")
}
def jobId = result.jobId

return [code: 200, payload: "The handler procedure has been started, job id is ${jobId}".getBytes(), headers: ['content-type': 'text/plain']]

def hmacSha1(String secretKey, String data) {
  try {
    Mac mac = Mac.getInstance("HmacSHA1")
    SecretKeySpec secretKeySpec = new SecretKeySpec(secretKey.getBytes(), "HmacSHA1")
    mac.init(secretKeySpec)
    byte[] digest = mac.doFinal(data.getBytes())
    return digest.encodeHex()
   }
  catch (InvalidKeyException e) {
    throw new RuntimeException("Invalid key exception while converting to HmacSHA1")
  }
}

def response(code, message) {
    return [code: code, message: message.toString(), headers: ['content-type': 'text/plain']]
}
