#!/usr/bin/env python3

# Copyright 2020, gRPC Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import json
import random
import string
import argparse

class Dependency:
    def __init__(self, name, version='s.version.to_s', useVerbatimVersion=True):
        self.name = name
        self.version = version
        self.useVerbatimVersion = useVerbatimVersion

    def as_podspec(self):
        if self.useVerbatimVersion:
            return "    s.dependency '%s', %s\n" % (self.name, self.version)
        else: 
            return "    s.dependency '%s', '%s'\n" % (self.name, self.version)

class Pod:
    def __init__(self, name, module_name, version, dependencies=None):
        self.name = name
        self.module_name = module_name
        self.version = version

        if dependencies is None:
            dependencies = []

        self.dependencies = dependencies
    
    def add_dependency(self, dependency):
        self.dependencies.append(dependency)
    
    def as_podspec(self):
        print('\n')
        print('Building Podspec for %s' % self.name)
        print('-----------------------------------------------------------')

        podspec = "Pod::Spec.new do |s|\n\n"
        podspec += "    s.name = '%s'\n" % self.name
        podspec += "    s.module_name = '%s'\n" % self.module_name
        podspec += "    s.version = '%s'\n" % self.version
        podspec += "    s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }\n"
        podspec += "    s.summary = 'Swift gRPC code generator plugin and runtime library'\n"
        podspec += "    s.homepage = 'https://www.grpc.io'\n"
        podspec += "    s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }\n\n"

        podspec += "    s.source = { :git => 'https://github.com/grpc/grpc-swift.git', :tag => s.version }\n\n"

        podspec += "    s.swift_version = '5.0'\n"

        podspec += "    s.ios.deployment_target = '10.0'\n"
        podspec += "    s.osx.deployment_target = '10.10'\n"
        podspec += "    s.tvos.deployment_target = '10.0'\n"
        
        podspec += "    s.source_files = 'Sources/%s/**/*.{swift,c,h}'\n" % (self.module_name)

        podspec += "\n" if len(self.dependencies) > 0 else ""

        for dep in self.dependencies:
            podspec += dep.as_podspec()

        podspec += "\nend"
        return podspec

class PodManager:
    pods = []

    def __init__(self, directory, version, should_publish):
        self.directory = directory
        self.version = version
        self.should_publish = should_publish

    def write(self, pod, contents):
        print('    Writing to %s/%s.podspec ' % (self.directory, pod))
        with open('%s/%s.podspec' % (self.directory, pod), 'w') as f: 
            f.write(contents)
    
    def publish(self, pod_name):
        os.system('pod repo update')
        print('    Publishing %s.podspec' % (pod_name))
        os.system('pod repo push %s/%s.podspec' % (self.directory, pod_name))
    
    def build_pods(self):
        CGRPCZlibPod = Pod('CGRPCZlib', 'CGRPCZlib', self.version)

        GRPCPod = Pod('gRPC-Swift', 'GRPC', self.version, get_grpc_deps())
        GRPCPod.add_dependency(Dependency('CGRPCZlib'))

        self.pods += [CGRPCZlibPod, GRPCPod]

    def go(self):
        self.build_pods()
        # Create .podspec files and publish
        for target in self.pods:
            self.write(target.name, target.as_podspec())
            if self.should_publish:
                self.publish(target.name)
            else:
                print('    Skipping Publishing...')

def process_package(string):
    pod_mappings = {
        'swift-log': 'Logging',
        'swift-nio': 'SwiftNIO',
        'swift-nio-http2': 'SwiftNIOHTTP2',
        'swift-nio-ssl': 'SwiftNIOSSL',
        'swift-nio-transport-services': 'SwiftNIOTransportServices',
        'SwiftProtobuf': 'SwiftProtobuf'
    }

    return pod_mappings[string]

def get_grpc_deps():
    with open('Package.resolved') as f:
        data = json.load(f)

    deps = []

    for obj in data['object']['pins']:
        package = process_package(obj['package'])
        version = obj['state']['version']

        deps.append(Dependency(package, version, False))

    return deps

def dir_path(string):
    if os.path.isdir(string):
        return string
    else:
        raise NotADirectoryError(string)

def main():
    # Setup

    parser = argparse.ArgumentParser(description='Build Podspec files for SwiftGRPC')
    
    parser.add_argument(
        '-p',
        '--path',
        type=dir_path,
        help='The directory where generated podspec files will be saved. If not passed, defaults to place in the current working directory.'
    )
    
    parser.add_argument(
        '-u', 
        '--upload',
        action='store_true',
        help='Determines if the newly built Podspec files should be pushed.'
    )
    
    parser.add_argument('version')

    args = parser.parse_args()

    should_publish = args.upload
    version = args.version
    path = args.path

    if not path:
        path = os.getcwd()

    pod_manager = PodManager(path, version, should_publish)
    pod_manager.go()

if __name__ == "__main__":
    main()