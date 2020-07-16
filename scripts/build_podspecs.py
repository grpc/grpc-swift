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

"""
Script for generating the gRPC-Swift and CGRPCZlib Podspec files.

    Usage:
        usage: build_podspecs.py [-h] [-p PATH] [-u] version

        Build Podspec files for SwiftGRPC

        positional arguments:
        version

        optional arguments:
        -h, --help            show this help message and exit
        -p PATH, --path PATH  The directory where generated podspec files will be
                                saved. If not passed, defaults to place in the current
                                working directory.
        -u, --upload          Determines if the newly built Podspec files should be
                                pushed.

    Example:
        'python scripts/build_podspecs.py -u 1.0.0-alpha.11'
"""

import os
import json
import random
import string
import argparse

class Dependency:
    def __init__(self, name, version='s.version.to_s', use_verbatim_version=True):
        self.name = name
        self.version = version
        self.use_verbatim_version = use_verbatim_version

    def as_podspec(self):
        indent='    '
        
        if self.use_verbatim_version:
            return indent + "s.dependency '%s', %s\n" % (self.name, self.version)

        return indent + "s.dependency '%s', '%s'\n" % (self.name, self.version)

class Pod:
    def __init__(self, name, module_name, version, description, dependencies=None, is_plugins_pod=False):
        self.name = name
        self.module_name = module_name
        self.version = version
        self.is_plugins_pod = is_plugins_pod

        if dependencies is None:
            dependencies = []

        self.dependencies = dependencies
        self.description = description

    def add_dependency(self, dependency):
        self.dependencies.append(dependency)

    def as_podspec(self):
        print('\n')
        print('Building Podspec for %s' % self.name)
        print('-----------------------------------------------------------')

        indent='    '
        
        podspec = "Pod::Spec.new do |s|\n\n"
        podspec += indent + "s.name = '%s'\n" % self.name
        if not self.is_plugins_pod:
            podspec += indent + "s.module_name = '%s'\n" % self.module_name
        podspec += indent + "s.version = '%s'\n" % self.version
        podspec += indent + "s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }\n"
        podspec += indent + "s.summary = '%s'\n" % self.description
        podspec += indent + "s.homepage = 'https://www.grpc.io'\n"
        podspec += indent + "s.authors  = { 'The gRPC contributors' => \'grpc-packages@google.com' }\n\n"

        podspec += indent + "s.swift_version = '5.0'\n"
        podspec += indent + "s.ios.deployment_target = '10.0'\n"
        podspec += indent + "s.osx.deployment_target = '10.12'\n"
        podspec += indent + "s.tvos.deployment_target = '10.0'\n"
        
        if self.is_plugins_pod:
            podspec += indent + "s.source = { :http => \"https://github.com/grpc/grpc-swift/releases/download/#{s.version}/protoc-grpc-swift-plugins-#{s.version}.zip\"}\n\n"
            podspec += indent + "s.preserve_paths = '*'\n"
        else:
            podspec += indent + "s.source = { :git => \"https://github.com/grpc/grpc-swift.git\", :tag => s.version }\n\n"
            podspec += indent + "s.source_files = 'Sources/%s/**/*.{swift,c,h}'\n" % (self.module_name)

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
        with open('%s/%s.podspec' % (self.directory, pod), 'w') as podspec_file:
            podspec_file.write(contents)

    def publish(self, pod_name):
        os.system('pod repo update')
        print('    Publishing %s.podspec' % (pod_name))
        os.system('pod trunk push --synchronous %s/%s.podspec' % (self.directory, pod_name))

    def build_pods(self):
        cgrpczlib_pod = Pod(
            'CGRPCZlib',
            'CGRPCZlib',
            self.version,
            'Compression library that provides in-memory compression and decompression functions'
        )

        grpc_pod = Pod(
            'gRPC-Swift',
            'GRPC',
            self.version,
            'Swift gRPC code generator plugin and runtime library',
            get_grpc_deps()
        )
        
        grpc_plugins_pod = Pod(
            'gRPC-Swift-Plugins',
            '',
            self.version,
            'Swift gRPC code generator plugin binaries',
            [],
            is_plugins_pod=True
        )

        grpc_pod.add_dependency(Dependency(cgrpczlib_pod.name))
        grpc_plugins_pod.add_dependency(Dependency(grpc_pod.name))

        self.pods += [cgrpczlib_pod, grpc_pod, grpc_plugins_pod]

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
    with open('Package.resolved') as package:
        data = json.load(package)

    deps = []

    for obj in data['object']['pins']:
        package = process_package(obj['package'])
        version = obj['state']['version']
        next_major_version = int(version.split('.')[0]) + 1

        deps.append(Dependency(package, '\'>= {}\', \'< {}\''.format(version, next_major_version)))

    return deps

def dir_path(path):
    if os.path.isdir(path):
        return path

    raise NotADirectoryError(path)

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

    return 0

if __name__ == "__main__":
    main()
