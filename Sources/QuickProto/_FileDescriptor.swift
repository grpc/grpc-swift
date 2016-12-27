/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

// GENERATED CODE

import Foundation

var _FileDescriptor : [[String:Any]] = [
  ["name": "FileDescriptorSet",
   "fields": [
    ["number":1, "name":"file", "label":3, "type":11, "type_name":".google.protobuf.FileDescriptorProto"],
    ]],
  ["name": "FileDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"package", "label":1, "type":9, "type_name":""],
    ["number":3, "name":"dependency", "label":3, "type":9, "type_name":""],
    ["number":10, "name":"public_dependency", "label":3, "type":5, "type_name":""],
    ["number":11, "name":"weak_dependency", "label":3, "type":5, "type_name":""],
    ["number":4, "name":"message_type", "label":3, "type":11, "type_name":".google.protobuf.DescriptorProto"],
    ["number":5, "name":"enum_type", "label":3, "type":11, "type_name":".google.protobuf.EnumDescriptorProto"],
    ["number":6, "name":"service", "label":3, "type":11, "type_name":".google.protobuf.ServiceDescriptorProto"],
    ["number":7, "name":"extension", "label":3, "type":11, "type_name":".google.protobuf.FieldDescriptorProto"],
    ["number":8, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.FileOptions"],
    ["number":9, "name":"source_code_info", "label":1, "type":11, "type_name":".google.protobuf.SourceCodeInfo"],
    ["number":12, "name":"syntax", "label":1, "type":9, "type_name":""],
    ]],
  ["name": "DescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"field", "label":3, "type":11, "type_name":".google.protobuf.FieldDescriptorProto"],
    ["number":6, "name":"extension", "label":3, "type":11, "type_name":".google.protobuf.FieldDescriptorProto"],
    ["number":3, "name":"nested_type", "label":3, "type":11, "type_name":".google.protobuf.DescriptorProto"],
    ["number":4, "name":"enum_type", "label":3, "type":11, "type_name":".google.protobuf.EnumDescriptorProto"],
    ["number":5, "name":"extension_range", "label":3, "type":11, "type_name":".google.protobuf.DescriptorProto.ExtensionRange"],
    ["number":8, "name":"oneof_decl", "label":3, "type":11, "type_name":".google.protobuf.OneofDescriptorProto"],
    ["number":7, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.MessageOptions"],
    ["number":9, "name":"reserved_range", "label":3, "type":11, "type_name":".google.protobuf.DescriptorProto.ReservedRange"],
    ["number":10, "name":"reserved_name", "label":3, "type":9, "type_name":""],
    ]],
  ["name": "ExtensionRange",
   "fields": [
    ["number":1, "name":"start", "label":1, "type":5, "type_name":""],
    ["number":2, "name":"end", "label":1, "type":5, "type_name":""],
    ]],
  ["name": "ReservedRange",
   "fields": [
    ["number":1, "name":"start", "label":1, "type":5, "type_name":""],
    ["number":2, "name":"end", "label":1, "type":5, "type_name":""],
    ]],
  ["name": "FieldDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":3, "name":"number", "label":1, "type":5, "type_name":""],
    ["number":4, "name":"label", "label":1, "type":14, "type_name":".google.protobuf.FieldDescriptorProto.Label"],
    ["number":5, "name":"type", "label":1, "type":14, "type_name":".google.protobuf.FieldDescriptorProto.Type"],
    ["number":6, "name":"type_name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"extendee", "label":1, "type":9, "type_name":""],
    ["number":7, "name":"default_value", "label":1, "type":9, "type_name":""],
    ["number":9, "name":"oneof_index", "label":1, "type":5, "type_name":""],
    ["number":10, "name":"json_name", "label":1, "type":9, "type_name":""],
    ["number":8, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.FieldOptions"],
    ]],
  ["name": "OneofDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ]],
  ["name": "EnumDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"value", "label":3, "type":11, "type_name":".google.protobuf.EnumValueDescriptorProto"],
    ["number":3, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.EnumOptions"],
    ]],
  ["name": "EnumValueDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"number", "label":1, "type":5, "type_name":""],
    ["number":3, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.EnumValueOptions"],
    ]],
  ["name": "ServiceDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"method", "label":3, "type":11, "type_name":".google.protobuf.MethodDescriptorProto"],
    ["number":3, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.ServiceOptions"],
    ]],
  ["name": "MethodDescriptorProto",
   "fields": [
    ["number":1, "name":"name", "label":1, "type":9, "type_name":""],
    ["number":2, "name":"input_type", "label":1, "type":9, "type_name":""],
    ["number":3, "name":"output_type", "label":1, "type":9, "type_name":""],
    ["number":4, "name":"options", "label":1, "type":11, "type_name":".google.protobuf.MethodOptions"],
    ["number":5, "name":"client_streaming", "label":1, "type":8, "type_name":""],
    ["number":6, "name":"server_streaming", "label":1, "type":8, "type_name":""],
    ]],
  ["name": "FileOptions",
   "fields": [
    ["number":1, "name":"java_package", "label":1, "type":9, "type_name":""],
    ["number":8, "name":"java_outer_classname", "label":1, "type":9, "type_name":""],
    ["number":10, "name":"java_multiple_files", "label":1, "type":8, "type_name":""],
    ["number":20, "name":"java_generate_equals_and_hash", "label":1, "type":8, "type_name":""],
    ["number":27, "name":"java_string_check_utf8", "label":1, "type":8, "type_name":""],
    ["number":9, "name":"optimize_for", "label":1, "type":14, "type_name":".google.protobuf.FileOptions.OptimizeMode"],
    ["number":11, "name":"go_package", "label":1, "type":9, "type_name":""],
    ["number":16, "name":"cc_generic_services", "label":1, "type":8, "type_name":""],
    ["number":17, "name":"java_generic_services", "label":1, "type":8, "type_name":""],
    ["number":18, "name":"py_generic_services", "label":1, "type":8, "type_name":""],
    ["number":23, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":31, "name":"cc_enable_arenas", "label":1, "type":8, "type_name":""],
    ["number":36, "name":"objc_class_prefix", "label":1, "type":9, "type_name":""],
    ["number":37, "name":"csharp_namespace", "label":1, "type":9, "type_name":""],
    ["number":38, "name":"javanano_use_deprecated_package", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "MessageOptions",
   "fields": [
    ["number":1, "name":"message_set_wire_format", "label":1, "type":8, "type_name":""],
    ["number":2, "name":"no_standard_descriptor_accessor", "label":1, "type":8, "type_name":""],
    ["number":3, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":7, "name":"map_entry", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "FieldOptions",
   "fields": [
    ["number":1, "name":"ctype", "label":1, "type":14, "type_name":".google.protobuf.FieldOptions.CType"],
    ["number":2, "name":"packed", "label":1, "type":8, "type_name":""],
    ["number":6, "name":"jstype", "label":1, "type":14, "type_name":".google.protobuf.FieldOptions.JSType"],
    ["number":5, "name":"lazy", "label":1, "type":8, "type_name":""],
    ["number":3, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":10, "name":"weak", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "EnumOptions",
   "fields": [
    ["number":2, "name":"allow_alias", "label":1, "type":8, "type_name":""],
    ["number":3, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "EnumValueOptions",
   "fields": [
    ["number":1, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "ServiceOptions",
   "fields": [
    ["number":33, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "MethodOptions",
   "fields": [
    ["number":33, "name":"deprecated", "label":1, "type":8, "type_name":""],
    ["number":999, "name":"uninterpreted_option", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption"],
    ]],
  ["name": "UninterpretedOption",
   "fields": [
    ["number":2, "name":"name", "label":3, "type":11, "type_name":".google.protobuf.UninterpretedOption.NamePart"],
    ["number":3, "name":"identifier_value", "label":1, "type":9, "type_name":""],
    ["number":4, "name":"positive_int_value", "label":1, "type":4, "type_name":""],
    ["number":5, "name":"negative_int_value", "label":1, "type":3, "type_name":""],
    ["number":6, "name":"double_value", "label":1, "type":1, "type_name":""],
    ["number":7, "name":"string_value", "label":1, "type":12, "type_name":""],
    ["number":8, "name":"aggregate_value", "label":1, "type":9, "type_name":""],
    ]],
  ["name": "NamePart",
   "fields": [
    ["number":1, "name":"name_part", "label":2, "type":9, "type_name":""],
    ["number":2, "name":"is_extension", "label":2, "type":8, "type_name":""],
    ]],
  ["name": "SourceCodeInfo",
   "fields": [
    ["number":1, "name":"location", "label":3, "type":11, "type_name":".google.protobuf.SourceCodeInfo.Location"],
    ]],
  ["name": "Location",
   "fields": [
    ["number":1, "name":"path", "label":3, "type":5, "type_name":""],
    ["number":2, "name":"span", "label":3, "type":5, "type_name":""],
    ["number":3, "name":"leading_comments", "label":1, "type":9, "type_name":""],
    ["number":4, "name":"trailing_comments", "label":1, "type":9, "type_name":""],
    ["number":6, "name":"leading_detached_comments", "label":3, "type":9, "type_name":""],
    ]],
];
