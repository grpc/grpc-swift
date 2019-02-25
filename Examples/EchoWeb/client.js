const {EchoRequest, EchoResponse} = require('./Generated/echo_pb.js');
const {EchoClient} = require('./Generated/echo_grpc_web_pb.js');

var client = new EchoClient('http://localhost:8080');

function sendMessage(message) {
  var request = new EchoRequest();
  request.setText(message);

  client.get(request, {}, (err, response) => {
    var responseLabel = document.getElementById("response_label")
    if (err) {
      responseLabel.innerText = "ERROR: Could not connect to the server."
    } else {
      responseLabel.innerText = "Server reply: " + response.getText()
    }
  });

  var expandStream = client.expand(request);
  expandStream.on('data', function(response) {
    console.log(response.getText());
  });
  expandStream.on('end', function(end) {
    console.log("Expand Stream Ended");
  });

}

window.addEventListener("DOMContentLoaded", function() {
  document.getElementById("message_button").addEventListener("click", function() {
    sendMessage(document.getElementById("input_field").value);
  });
}, false);
