
�

echo.protoecho"!
EchoRequest
text (	Rtext""
EchoResponse
text (	Rtext2�
Echo.
Get.echo.EchoRequest.echo.EchoResponse" 3
Expand.echo.EchoRequest.echo.EchoResponse" 04
Collect.echo.EchoRequest.echo.EchoResponse" (5
Update.echo.EchoRequest.echo.EchoResponse" (0J�

 (
�
 2� Copyright (c) 2015, Google Inc.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.


 


  


 
8
  0+ Immediately returns an echo of a request.


  	

  


   ,
Y
 :L Splits a request into words and returns each word in a stream of messages.


 

 

 #)

 *6
b
 ;U Collects a stream of messages and returns them concatenated when the caller closes.


 

 

  

 +7
M
 A@ Streams back messages as they are received in an input stream.


 

 

 

 *0

 1=


   #


  
2
  "% The text of a message to be echoed.


  "

  "	

  "


% (


%
,
 ' The text of an echo response.


 '

 '	

 'bproto3