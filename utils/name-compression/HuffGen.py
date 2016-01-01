#!/usr/bin/env python

import sys
from heapq import heappush, heappop
from collections import defaultdict

filenames = sys.argv[1:]
if len(filenames) == 0:
  print "-- Huffman encoding generation tool -- "
  print "Usage: ./HuffGen.py file1.txt file2.txt file3.txt ..."
  sys.exit(1)

hist = defaultdict(int)

def addLine(line):
  """
  Analyze the frequency of letters in \p line.
  """
  for c in line: hist[c] += 1

# Read all of the input files and analyze the content of the files.
for f in filenames:
  for line in open(f):
    addLine(line.rstrip('\n').strip())

# Sort all of the characters by their appearance frequency.
sorted_chars = sorted(hist.items(), key=lambda x: x[1] * len(x[0]) , reverse=True)

class Node:
  """ This is a node in the Huffman tree """
  def __init__(self, hits, value = None, l = None, r = None):
    self.hit = hits  # Number of occurrences for this node.
    self.left = l    # Left subtree.
    self.right = r   # Right subtree.
    self.val = value # Character value for leaf nodes.

  def merge(Left, Right):
    """ This is the merge phase of the huffman encoding algorithm
        This (static) method creates a new node that combines \p Left and \p Right.
    """
    return Node(Left.hit + Right.hit, None, Left, Right)

  def __cmp__(self, other):
    """ Compare this node to another node based on their frequency. """
    return self.hit > other.hit

  def getMaxEncodingLength(self):
    """ Return the length of the longest possible encoding word"""
    v = 1
    if self.left:  v = max(v, 1 + self.left .getMaxEncodingLength())
    if self.right: v = max(v, 1 + self.right.getMaxEncodingLength())
    return v

  def generate_decoder(self, depth):
    """
    Generate the CPP code for the decoder.
    """
    space = " " * depth

    if self.val:
      return space + "num = num.lshr(%d);\n" % depth +\
             space + "return \'" + str(self.val) + "\';"

    T = """{0}if ((tailbits & 1) == {1}) {{\n{0} tailbits/=2;\n{2}\n{0}}}"""
    sb = ""
    if self.left:  sb += T.format(space, 0, self.left .generate_decoder(depth + 1)) + "\n"
    if self.right: sb += T.format(space, 1, self.right.generate_decoder(depth + 1))
    return sb

  def generate_encoder(self, stack):
    """
    Generate the CPP code for the encoder.
    """
    if self.val:
      sb = "if (ch == '" + str(self.val) +"') {"
      sb += "/*" +  "".join(map(str, reversed(stack))) + "*/ "
      # Encode the bit stream as a numeric value. Updating the APInt in one go
      # is much faster than inserting one bit at a time.
      numeric_val = 0
      for bit in reversed(stack): numeric_val = numeric_val * 2 + bit
      # Shift the value to make room in the bitstream and then add the numeric
      # value that represents the sequence of bits that we need to add.
      sb += "num = num.shl(%d); " % len(stack)
      sb += "num = num + %d; " % (numeric_val)
      sb += "return; }\n"
      return sb
    sb = ""
    if (self.left):  sb += self.left .generate_encoder(stack + [0])
    if (self.right): sb += self.right.generate_encoder(stack + [1])
    return sb

# Only accept these characters into the tree.
charset = r"0123456789_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ$"
charset_length = str(len(charset))

# Convert the characters and frequencies to a list of trees
# where each tree is a node that holds a single character.
nodes = []
for c in sorted_chars:
  if c[0] in charset:
    n = Node(c[1],c[0])
    heappush(nodes, n)

# This is the Merge phase of the Huffman algorithm:
while len(nodes) > 1:
  v1 = heappop(nodes)
  v2 = heappop(nodes)
  nv = Node.merge(v1, v2)
  heappush(nodes, nv)

print "#ifndef SWIFT_MANGLER_HUFFMAN_H"
print "#define SWIFT_MANGLER_HUFFMAN_H"
print "#include <assert.h>"
print "#include \"llvm/ADT/APInt.h\""
print "using APInt = llvm::APInt;"
print "// This file is autogenerated. Do not modify this file."
print "// Processing text files:", " ".join(filenames)
print "namespace Huffman {"
print "// The charset that the fragment indices can use:"
print "unsigned CharsetLength = %d;" % len(charset)
print "unsigned LongestEncodingLength = %d;" % (nodes[0].getMaxEncodingLength())
print "const char *Charset = \"%s\";" % charset
print "char variable_decode(APInt &num) {\n uint64_t tailbits = *num.getRawData();\n", nodes[0].generate_decoder(0), "\n assert(false); return 0;\n}"
print "void variable_encode(APInt &num, char ch) {\n", nodes[0].generate_encoder([]),"assert(false);\n}"
print "} // namespace"
print "#endif /* SWIFT_MANGLER_HUFFMAN_H */"
