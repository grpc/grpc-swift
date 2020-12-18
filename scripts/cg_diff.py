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
import argparse
import enum
import os
import subprocess
import sys


class State(enum.Enum):
    READING_HEADERS = enum.auto()
    READING_INSTRUCTION = enum.auto()
    READING_COUNTS = enum.auto()
    READING_SUMMARY = enum.auto()


class InstructionCounts(object):
    def __init__(self, events):
        self._events = events
        self._counts = {}

    @property
    def events(self):
        return self._events

    @property
    def instructions(self):
        return self._counts.keys()

    def add(self, instruction, counts):
        """Add a list of counts or the given instruction."""
        if instruction in self._counts:
            existing = self._counts[instruction]
            self._counts[instruction] = [a + b for (a, b) in zip(existing, counts)]
        else:
            self._counts[instruction] = counts

    def count(self, instruction, event):
        """The number of occurrences of the event for the given instruction."""
        counts = self._counts.get(instruction)
        index = self._events.index(event)
        if counts:
            return counts[index]
        else:
            return 0

    def aggregate(self):
        """Aggregates event counts over all instructions."""
        return [sum(x) for x in zip(*self._counts.values())]

    def aggregate_by_event(self, event):
        """Aggregates event counts over all instructions for a given event."""
        return self.aggregate_by_index(self._events.index(event))

    def aggregate_by_index(self, index):
        """Aggregates event counts over all instructions for the event at the given index."""
        return sum(x[index] for x in self._counts.values())


class Parser(object):
    HEADERS = ["desc:", "cmd:"]

    def __init__(self):
        # Parsing state.
        self._state = State.READING_HEADERS
        # File for current instruction
        self._file = None
        # Function for current instruction
        self._function = None
        # Instruction counts
        self._counts = None

    @property
    def counts(self):
        return self._counts

    @property
    def _key(self):
        fl = "???" if self._file is None else self._file
        fn = "???" if self._function is None else self._function
        return fl + ":" + fn

    ### Helpers

    def _is_header(self, line):
        return any(line.startswith(p) for p in Parser.HEADERS)

    def _read_events_header(self, line):
        if line.startswith("events:"):
            self._counts = InstructionCounts(line[7:].strip().split(" "))
            return True
        else:
            return False

    def _read_function(self, line):
        if not line.startswith("fn="):
            return None
        return line[3:].strip()

    def _read_file(self, line):
        if not line.startswith("fl="):
            return None
        return line[3:].strip()

    def _read_file_or_function(self, line, reset_instruction=False):
        function = self._read_function(line)
        if function is not None:
            self._function = function
            self._file = None if reset_instruction else self._file
            return State.READING_INSTRUCTION

        file = self._read_file(line)
        if file is not None:
            self._file = file
            self._function = None if reset_instruction else self._function
            return State.READING_INSTRUCTION

        return None

    ### Section parsing

    def _read_headers(self, line):
        if self._read_events_header(line) or self._is_header(line):
            # Still reading headers.
            return State.READING_HEADERS

        # Not a header, maybe a file or function.
        next_state = self._read_file_or_function(line)
        if next_state is None:
            raise RuntimeWarning("Unhandled line:", line)

        return next_state

    def _read_instruction(self, line, reset_instruction=False):
        next_state = self._read_file_or_function(line, reset_instruction)
        if next_state is not None:
            return next_state

        if self._read_summary(line):
            return State.READING_SUMMARY

        return self._read_counts(line)

    def _read_counts(self, line):
        # Drop the line number
        counts = [int(x) for x in line.split(" ")][1:]
        self._counts.add(self._key, counts)
        return State.READING_COUNTS

    def _read_summary(self, line):
        if line.startswith("summary:"):
            summary = [int(x) for x in line[8:].strip().split(" ")]
            computed_summary = self._counts.aggregate()
            assert summary == computed_summary
            return True
        else:
            return False

    ### Parse

    def parse(self, file, demangle):
        """Parse the given file."""
        with open(file) as fh:
            if demangle:
                demangled = subprocess.check_output(["swift", "demangle"], stdin=fh)
                self._parse_lines(x.decode("utf-8") for x in demangled.splitlines())
            else:
                self._parse_lines(fh)

        return self._counts

    def _parse_lines(self, lines):
        for line in lines:
            self._next_line(line)

    def _next_line(self, line):
        """Parses a line of input."""
        if self._state is State.READING_HEADERS:
            self._state = self._read_headers(line)
        elif self._state is State.READING_INSTRUCTION:
            self._state = self._read_instruction(line)
        elif self._state is State.READING_COUNTS:
            self._state = self._read_instruction(line, reset_instruction=True)
        elif self._state is State.READING_SUMMARY:
            # We're done.
            return
        else:
            raise RuntimeError("Unexpected state", self._state)


def parse(filename, demangle):
    parser = Parser()
    return parser.parse(filename, demangle)


def print_summary(args):
    # No need to demangle for summary.
    counts1 = parse(args.file1, False)
    aggregate1 = counts1.aggregate_by_event(args.event)
    counts2 = parse(args.file2, False)
    aggregate2 = counts2.aggregate_by_event(args.event)

    delta = aggregate2 - aggregate1
    pc = 100.0 * delta / aggregate1
    print("{:16,} {}".format(aggregate1, os.path.basename(args.file1)))
    print("{:16,} {}".format(aggregate2, os.path.basename(args.file2)))
    print("{:+16,} ({:+.3f}%)".format(delta, pc))


def print_diff_table(args):
    counts1 = parse(args.file1, args.demangle)
    aggregate1 = counts1.aggregate_by_event(args.event)
    counts2 = parse(args.file2, args.demangle)
    aggregate2 = counts2.aggregate_by_event(args.event)

    file1_total = aggregate1
    diffs = []

    def _count(key, counts):
        block = counts.get(key)
        return 0 if block is None else block.counts[0]

    def _row(c1, c2, key):
        delta = c2 - c1
        delta_pc = 100.0 * (delta / file1_total)
        return (c1, c2, delta, delta_pc, key)

    def _row_for_key(key):
        c1 = counts1.count(key, args.event)
        c2 = counts2.count(key, args.event)
        return _row(c1, c2, key)

    if args.only_common:
        keys = counts1.instructions & counts2.instructions
    else:
        keys = counts1.instructions | counts2.instructions

    rows = [_row_for_key(k) for k in keys]
    rows.append(_row(aggregate1, aggregate2, "PROGRAM TOTALS"))

    print(
        " | ".join(
            [
                "file1".rjust(14),
                "file2".rjust(14),
                "delta".rjust(14),
                "%".rjust(7),
                "name",
            ]
        )
    )

    index = _sort_index(args.sort)
    reverse = not args.ascending
    sorted_rows = sorted(rows, key=lambda x: x[index], reverse=reverse)
    for (c1, c2, delta, delta_pc, key) in sorted_rows:
        if abs(delta_pc) >= args.low_watermark:
            print(
                " | ".join(
                    [
                        "{:14,}".format(c1),
                        "{:14,}".format(c2),
                        "{:+14,}".format(delta),
                        "{:+7.3f}".format(delta_pc),
                        key,
                    ]
                )
            )


def _sort_index(key):
    return ("file1", "file2", "delta").index(key)


if __name__ == "__main__":
    parser = argparse.ArgumentParser("cg_diff.py")

    parser.add_argument(
        "--sort",
        choices=("file1", "file2", "delta"),
        default="file1",
        help="The column to sort on.",
    )

    parser.add_argument(
        "--ascending", action="store_true", help="Sorts in ascending order."
    )

    parser.add_argument(
        "--only-common",
        action="store_true",
        help="Only print instructions present in both files.",
    )

    parser.add_argument(
        "--no-demangle",
        action="store_false",
        dest="demangle",
        help="Disables demangling of input files.",
    )

    parser.add_argument("--event", default="Ir", help="The event to compare.")

    parser.add_argument(
        "--low-watermark",
        type=float,
        default=0.01,
        help="A low watermark, percentage changes in counts "
        "relative to the total instruction count of "
        "file1 below this value will not be printed.",
    )

    parser.add_argument(
        "--summary", action="store_true", help="Prints a summary of the diff."
    )

    parser.add_argument("file1")
    parser.add_argument("file2")

    args = parser.parse_args()

    if args.summary:
        print_summary(args)
    else:
        print_diff_table(args)
