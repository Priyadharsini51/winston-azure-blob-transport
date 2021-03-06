_ = require "lodash"
vows = require "vows"
async = require "async"
sinon = require "sinon"
should = require "should"
require "should-sinon"
proxyquire = require "proxyquire"
helpers = require "winston/test/helpers"

azure = require "azure-storage"
MAX_BLOCK_SIZE = azure.Constants.BlobConstants.MAX_BLOCK_SIZE

mockAzure = (mock) ->
  "azure-storage":
    createBlobService: -> mock

transportWithStub = ({ nameResolver } = {}) ->
  stub = mockAzure appendFromText: sinon.stub().callsArgWith 3, null, null
  AzureBlobTransport = proxyquire("./blobTransport", stub)
  new AzureBlobTransport {
    account:
      name: "accountName"
      key: "accountKey"
    containerName: "containerName"
    blobName: "blobName"
    nameResolver
  }

testLogInBlocksSucessfully = ({messages: { sampleMessage, n = 1 }, calls = 1}) ->
  "when log #{n} line(s) with length #{sampleMessage.length}":
    "topic": ->
      transport = transportWithStub()
      callback = sinon.spy()

      lines = _.times n, _.constant(sampleMessage)
      for line in lines
        transport.log "INFO", line, {}, callback

      setTimeout =>
        @callback null, { transport, callback }
      , 2000

      return

    "should be call #{calls} time(s) to Azure": ({ transport }) ->
      transport.client.appendFromText.should.have.callCount calls

    "should be call #{n} time(s) to success callback": ({ callback }) ->
      callback.should.have.callCount n

    "should be called with file and container": ({ transport }) ->
      transport.client.appendFromText.alwaysCalledWithMatch "containerName", "blobName", sinon.match.string, sinon.match.function

testWithCustomNameResolver = ->
  "use custom name resolver to save in a blob":

    "topic": ->
      nameResolver = getBlobName: sinon.spy _.constant("otherBlobName")
      transport = transportWithStub { nameResolver }

      lines = _.times 10, (i) -> transport.log "INFO", "line #{i}", {}, _.noop

      setTimeout =>
        @callback null, { transport, nameResolver }
      , 2000

      return

    "should be called with file and container": ({ transport, nameResolver }) ->
      nameResolver.getBlobName.should.have.callCount 1
      transport.client.appendFromText.alwaysCalledWithMatch "containerName", "otherBlobName", sinon.match.string, sinon.match.function

sample = (n) ->
  paddingLeft = "[INFO] - #{new Date().toISOString()} - ".length
  paddingRight = "\n".length
  maxSizeMessage = n - paddingLeft - paddingRight
  _.repeat "*", maxSizeMessage

tests = _.merge(
  helpers.testNpmLevels(transportWithStub(), "should log messages to azure blob", (ign, err, logged) ->
    should(err).be.null()
    logged.should.be.not.null()
  ),
  testLogInBlocksSucessfully(
    messages:
      sampleMessage: sample 100
  ),
  testLogInBlocksSucessfully(
    messages:
      sampleMessage: sample 100
      n: 10
  ),
  testLogInBlocksSucessfully(
    messages:
      sampleMessage: sample MAX_BLOCK_SIZE - 1
  ),
  testLogInBlocksSucessfully(
    messages:
      sampleMessage: sample MAX_BLOCK_SIZE + 1
    calls: 2
  ),
  testWithCustomNameResolver()
)

vows.describe("winston-azure-blob-transport").addBatch(
  "the log() method": tests
).export(module);
