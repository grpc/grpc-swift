// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "EchoViewController.h"

#import "echoapi/Echo.pbobjc.h"
#import "echoapi/Echo.pbrpc.h"
#import <GRPCClient/GRPCCall.h>
#import <GRPCClient/GRPCCall+Tests.h> // this allows us to disable TLS
#import <RxLibrary/GRXBufferedPipe.h>

#import <ProtoRPC/ProtoRPC.h>

// [START host]
static NSString * const kHostAddress = @"localhost";
// [END host]
// = @"<IP Address>"; // GCE instance
// = @"<IP Address>"; // L4 load balancer

static BOOL useSSL = NO;

@interface EchoViewController () <UITextFieldDelegate>
@property (nonatomic, strong) IBOutlet UITextField *echoField;
@property (nonatomic, strong) IBOutlet UITextField *textField;
@property (nonatomic, strong) IBOutlet UISwitch *streamSwitch;

@property (nonatomic, strong) NSString *addressWithPort;

@property (nonatomic, strong) Echo *client;
@property (nonatomic, strong) GRPCProtoCall *updateCall;
@property (nonatomic, strong) GRXBufferedPipe *writer;

@end

@implementation EchoViewController

- (void) viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor darkGrayColor];

  [self configureNetworking];
}

- (void) configureNetworking {
  if (!useSSL) {
    _addressWithPort = [kHostAddress stringByAppendingString:@":8080"];
    // This tells the GRPC library to NOT use SSL.
    [GRPCCall useInsecureConnectionsForHost:_addressWithPort];
  } else {
    _addressWithPort = [kHostAddress stringByAppendingString:@":443"];
    // This tells the GRPC library to trust a certificate that it might not be able to validate.
    // Typically this would be used to trust a self-signed certificate.
    [GRPCCall useTestCertsPath:[[NSBundle mainBundle] pathForResource:@"ssl" ofType:@"crt"]
                      testName:@"example.com"
                       forHost:kHostAddress
     ];
  }
  _client = [[Echo alloc] initWithHost:_addressWithPort];
}

- (void) getStickynoteWithMessage:(NSString *) message {
  EchoRequest *request = [EchoRequest message];
  request.text = message;
  GRPCProtoCall *call = [_client RPCToGetWithRequest:request
                                             handler:
                         ^(EchoResponse *response, NSError *error) {
                           [self handleEchoResponse:response andError:error];
                         }];
  [call start];
}

// [START openStreamingConnection]
- (void) openStreamingConnection {
  _writer = [[GRXBufferedPipe alloc] init];
  _updateCall = [_client RPCToUpdateWithRequestsWriter:_writer
                                          eventHandler:^(BOOL done, EchoResponse *response, NSError *error) {
                                            [self handleEchoResponse:response andError:error];
                                          }];
  [_updateCall start];
}
// [END openStreamingConnection]

- (void) closeStreamingConnection {
  [_writer writesFinishedWithError:nil];
}

- (void) handleEchoResponse:(EchoResponse *)response andError:(NSError *) error {
  if (error) {
    self.echoField.backgroundColor = [UIColor redColor];
    self.echoField.text = @"";
    NSLog(@"ERROR: %@", error);
  } else if (response.text) {
    self.echoField.backgroundColor = [UIColor whiteColor];
    self.echoField.text = response.text;
  }
}

- (IBAction) textFieldDidEndEditing:(UITextField *)textField
{
  [self getStickynoteWithMessage:textField.text];
}

// [START textDidChange]
- (IBAction)textDidChange:(UITextField *) sender {
  if ([_streamSwitch isOn]) {
    EchoRequest *request = [EchoRequest message];
    request.text = sender.text;
    [_writer writeValue:request];
  }
}
// [END textDidChange]

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  [textField resignFirstResponder];
  return NO;
}

- (IBAction) switchValueDidChange:(UISwitch *) sender {
  if ([sender isOn]) {
    [self openStreamingConnection];
  } else {
    [self closeStreamingConnection];
  }
}

- (UIStatusBarStyle) preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}

@end
