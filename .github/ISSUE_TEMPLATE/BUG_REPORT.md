---
name: 🐛 Bug Report
about: If something isn't working as expected 🤔
labels: bug
---

<!--
Please check the README, docs/ directory and other issues before filing an issue.

This form is for submitting BUG REPORTS only.

For troubleshooting or new feature requests please use one of the other templates.
-->

### Describe the bug

Describe the bug as clearly and as concisely as you can. Without enough
information, we will not be able to help you.

Include the version of `grpc-swift` and `protoc-gen-grpc-swift` you are using
(or the Podspec version if you are using CocoaPods), how you are building the
code (eg. `swift build -c release`) as well as the platform(s) on which you
experienced the bug.

If the bug is a performance bug, please double check you are building in
release mode.

### To reproduce

Steps to reproduce the bug you've found:
1. Set compression to ...
2. Make a bidirectional RPC to ...
3. ...

### Expected behaviour

Describe what you expect to happen when the steps above are followed.

### Additional information

Include any information that you think might help us to diagnose and resolve
this more quickly, such as logs, code snippets, or similar cases where the bug
does not reproduce. (Please wrap code snippets and logs in backticks though!)
