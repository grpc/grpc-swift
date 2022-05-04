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
import subprocess
import sys


class TargetDependency(object):
    def __init__(self, name):
        self.name = name

    def __str__(self):
        return "s.dependency '{name}', s.version.to_s".format(name=self.name)


class ProductDependency(object):
    def __init__(self, name, lower, upper):
        self.name = name
        self.lower = lower
        self.upper = upper

    def __str__(self):
        return "s.dependency '{name}', '>= {lower}', '< {upper}'".format(
                name=self.name, lower=self.lower, upper=self.upper)


class Pod:
    def __init__(self, name, module_name, version, description, dependencies=None, is_plugins_pod=False):
        self.name = name
        self.module_name = module_name
        self.version = version
        self.is_plugins_pod = is_plugins_pod
        self.dependencies = dependencies if dependencies is not None else []
        self.description = description

    def as_podspec(self):
        print('\n')
        print('Building Podspec for %s' % self.name)
        print('-' * 80)

        indent=' ' * 4

        podspec = "Pod::Spec.new do |s|\n\n"
        podspec += indent + "s.name = '%s'\n" % self.name
        if not self.is_plugins_pod:
            podspec += indent + "s.module_name = '%s'\n" % self.module_name
        podspec += indent + "s.version = '%s'\n" % self.version
        podspec += indent + "s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }\n"
        podspec += indent + "s.summary = '%s'\n" % self.description
        podspec += indent + "s.homepage = 'https://www.grpc.io'\n"
        podspec += indent + "s.authors  = { 'The gRPC contributors' => \'grpc-packages@google.com' }\n\n"

        podspec += indent + "s.swift_version = '5.4'\n"
        podspec += indent + "s.ios.deployment_target = '10.0'\n"
        podspec += indent + "s.osx.deployment_target = '10.12'\n"
        podspec += indent + "s.tvos.deployment_target = '10.0'\n"
        podspec += indent + "s.watchos.deployment_target = '6.0'\n"

        if self.is_plugins_pod:
            podspec += indent + "s.source = { :http => \"https://github.com/grpc/grpc-swift/releases/download/#{s.version}/protoc-grpc-swift-plugins-#{s.version}.zip\"}\n\n"
            podspec += indent + "s.preserve_paths = '*'\n"
        else:
            podspec += indent + "s.source = { :git => \"https://github.com/grpc/grpc-swift.git\", :tag => s.version }\n\n"
            podspec += indent + "s.source_files = 'Sources/%s/**/*.{swift,c,h}'\n" % (self.module_name)

            podspec += "\n" if len(self.dependencies) > 0 else ""

        for dep in sorted(self.dependencies, key=lambda x: x.name):
            podspec += indent + str(dep) + "\n"

        podspec += "\nend"
        return podspec

class PodManager:
    def __init__(self, directory, version, should_publish, package_dump):
        self.directory = directory
        self.version = version
        self.should_publish = should_publish
        self.package_dump = package_dump

    def write(self, pod, contents):
        print('    Writing to %s/%s.podspec ' % (self.directory, pod))
        with open('%s/%s.podspec' % (self.directory, pod), 'w') as podspec_file:
            podspec_file.write(contents)

    def publish(self, pod_name):
        subprocess.check_call(['pod', 'repo', 'update'])
        print('    Publishing %s.podspec' % (pod_name))

        args = ['pod', 'trunk', 'push', '--synchronous']

        # The gRPC-Swift pod emits warnings about redundant availability
        # guards on watchOS. These are redundant for the Cocoapods where we set
        # the deployment target for watchOS to watchOS 6. However they are
        # required for SPM where the deployment target is lower (and we can't
        # raise it without breaking all of our consumers). We'll allow warnings
        # to work around this.
        if pod_name == "gRPC-Swift":
            args.append("--allow-warnings")

        path_to_podspec = self.directory + '/' + pod_name + ".podspec"
        args.append(path_to_podspec)
        subprocess.check_call(args)

    def build_pods(self):
        cgrpczlib_pod = Pod(
            self.pod_name_for_grpc_target('CGRPCZlib'),
            'CGRPCZlib',
            self.version,
            'Compression library that provides in-memory compression and decompression functions',
            dependencies=self.build_dependency_list('CGRPCZlib')
        )

        grpc_pod = Pod(
            self.pod_name_for_grpc_target('GRPC'),
            'GRPC',
            self.version,
            'Swift gRPC code generator plugin and runtime library',
            dependencies=self.build_dependency_list('GRPC')
        )

        grpc_plugins_pod = Pod(
            'gRPC-Swift-Plugins',
            '',
            self.version,
            'Swift gRPC code generator plugin binaries',
            dependencies=[TargetDependency("gRPC-Swift")],
            is_plugins_pod=True
        )

        return [cgrpczlib_pod, grpc_pod, grpc_plugins_pod]

    def go(self, start_from):
        pods = self.build_pods()

        if start_from:
            pods = pods[list(pod.name for pod in pods).index(start_from):]

        # Create .podspec files and publish
        for target in pods:
            self.write(target.name, target.as_podspec())
            if self.should_publish:
                self.publish(target.name)
            else:
                print('    Skipping Publishing...')


    def pod_name_for_package(self, name):
        """Return the CocoaPod name for a given Swift package."""
        pod_mappings = {
            'swift-log': 'Logging',
            'swift-nio': 'SwiftNIO',
            'swift-nio-extras': 'SwiftNIOExtras',
            'swift-nio-http2': 'SwiftNIOHTTP2',
            'swift-nio-ssl': 'SwiftNIOSSL',
            'swift-nio-transport-services': 'SwiftNIOTransportServices',
            'SwiftProtobuf': 'SwiftProtobuf'
        }
        return pod_mappings[name]


    def pod_name_for_grpc_target(self, name):
        """Return the CocoaPod name for a given gRPC Swift target."""
        return {
          'GRPC': 'gRPC-Swift',
          'CGRPCZlib': 'CGRPCZlib'
        }[name]


    def get_package_requirements(self, package_name):
        """
        Returns the lower and upper bound version requirements for a given
        package dependency.
        """
        for dependency in self.package_dump['dependencies']:
            if dependency['name'] == package_name:
                # There should only be 1 range.
                requirement = dependency['requirement']['range'][0]
                return (requirement['lowerBound'], requirement['upperBound'])

        # This shouldn't happen.
        raise ValueError('Could not find package called', package_name)


    def get_dependencies(self, target_name):
        """
        Returns a tuple of dependency lists for a given target.

        The first entry is the list of product dependencies; dependencies on
        products from other packages. The second entry is a list of target
        dependencies, i.e. dependencies on other targets within the package.
        """
        for target in self.package_dump['targets']:
            if target['name'] == target_name:
                product_dependencies = set()
                target_dependencies = []

                for dependency in target['dependencies']:
                    if 'product' in dependency:
                        product_dependencies.add(dependency['product'][1])
                    elif 'target' in dependency:
                        target_dependencies.append(dependency['target'][0])
                    else:
                        raise ValueError('Unexpected dependency type:', dependency)

                return (product_dependencies, target_dependencies)

        # This shouldn't happen.
        raise ValueError('Could not find dependency called', target_name)


    def build_dependency_list(self, target_name):
        """
        Returns a list of dependencies for the given target.

        Dependencies may be either 'TargetDependency' or 'ProductDependency'.
        """
        product, target = self.get_dependencies(target_name)
        dependencies = []

        for package_name in product:
            (lower, upper) = self.get_package_requirements(package_name)
            pod_name = self.pod_name_for_package(package_name)
            dependencies.append(ProductDependency(pod_name, lower, upper))

        for target_name in target:
            pod_name = self.pod_name_for_grpc_target(target_name)
            dependencies.append(TargetDependency(pod_name))

        return dependencies


def dir_path(path):
    if os.path.isdir(path):
        return path

    raise NotADirectoryError(path)

def main():
    parser = argparse.ArgumentParser(description='Build Podspec files for gRPC Swift')

    parser.add_argument(
        '-p',
        '--path',
        type=dir_path,
        help='The directory where generated podspec files will be saved. If not passed, defaults to the current working directory.'
    )

    parser.add_argument(
        '-u',
        '--upload',
        action='store_true',
        help='Determines if the newly built Podspec files should be pushed.'
    )

    parser.add_argument(
        '-f',
        '--start-from',
        help='The name of the Podspec to start from.'
    )

    parser.add_argument('version')
    args = parser.parse_args()

    should_publish = args.upload
    version = args.version
    path = args.path
    start_from = args.start_from

    if not path:
        path = os.getcwd()

    print("Reading package description...")
    lines = subprocess.check_output(["swift", "package", "dump-package"])
    package_dump = json.loads(lines)
    assert(package_dump["name"] == "grpc-swift")

    pod_manager = PodManager(path, version, should_publish, package_dump)
    pod_manager.go(start_from)

    return 0

if __name__ == "__main__":
    main()
