// RUN: %target-swift-frontend -O -emit-sil %s | FileCheck %s

public protocol Foo { 
  func foo(_ x:Int) -> Int
}

public extension Foo {
  func boo(_ x:Int) -> Int32 {
    return 2222 + x
  }

  func getSelf() -> Self {
    return self
  }
}

var gg = 1111

public class C : Foo {
  @inline(never)
  public func foo(_ x:Int) -> Int {
    gg += 1
    return gg + x
  }
}

@_transparent
func callfoo(_ f: Foo) -> Int {
  return f.foo(2) + f.foo(2)
}

@_transparent
func callboo(_ f: Foo) -> Int32 {
  return f.boo(2) + f.boo(2)
}

@_transparent
func callGetSelf(_ f: Foo) -> Foo {
  return f.getSelf()
}

// Check that methods returning Self are not devirtualized and do not crash the compiler.
// CHECK-LABEL: sil [noinline] @_TF34devirt_protocol_method_invocations70test_devirt_protocol_extension_method_invocation_with_self_return_typeFCS_1CPS_3Foo_
// CHECK: init_existential_addr
// CHECK: open_existential_addr
// CHECK: return
@inline(never)
public func test_devirt_protocol_extension_method_invocation_with_self_return_type(_ c: C) -> Foo {
  return callGetSelf(c)
}

// It's not obvious why this isn't completely devirtualized.
// CHECK: sil @_TF34devirt_protocol_method_invocations12test24114020FT_Si
// CHECK:   [[T0:%.*]] = alloc_stack $SimpleBase
// CHECK:   [[T1:%.*]] = witness_method $SimpleBase, #Base.x!getter.1 
// CHECK:   [[T2:%.*]] = apply [[T1]]<SimpleBase>([[T0]])
// CHECK:   return [[T2]]

// CHECK: sil @_TF34devirt_protocol_method_invocations14testExMetatypeFT_Si
// CHECK:   [[T0:%.*]] = builtin "sizeof"<Int>
// CHECK:   [[T1:%.*]] = builtin {{.*}}([[T0]]
// CHECK:   [[T2:%.*]] = struct $Int ([[T1]] : {{.*}})
// CHECK:   return [[T2]] : $Int

// Check that calls to f.foo() get devirtualized and are not invoked
// via the expensive witness_method instruction.
// To achieve that the information about a concrete type C should
// be propagated from init_existential_addr into witness_method and 
// apply instructions.

// CHECK-LABEL: sil [noinline] @_TTSf4g___TF34devirt_protocol_method_invocations38test_devirt_protocol_method_invocationFCS_1CSi
// CHECK-NOT: witness_method
// CHECK: checked_cast
// CHECK-NOT: checked_cast
// CHECK: bb1(
// CHECK-NOT: checked_cast
// CHECK: return
// CHECK: bb2(
// CHECK-NOT: checked_cast
// CHECK: function_ref
// CHECK: apply
// CHECK: apply
// CHECK: br bb1(
// CHECK: bb3
// CHECK-NOT: checked_cast
// CHECK: apply
// CHECK: apply
// CHECK: br bb1(
@inline(never)
public func test_devirt_protocol_method_invocation(_ c: C) -> Int {
  return callfoo(c)
}

// Check that calls of a method boo() from the protocol extension
// get devirtualized and are not invoked via the expensive witness_method instruction
// or by passing an existential as a parameter.
// To achieve that the information about a concrete type C should
// be propagated from init_existential_addr into apply instructions.
// In fact, the call is expected to be inlined and then constant-folded
// into a single integer constant.

// CHECK-LABEL: sil [noinline] @_TTSf4dg___TF34devirt_protocol_method_invocations48test_devirt_protocol_extension_method_invocationFCS_1CVs5Int32
// CHECK-NOT: checked_cast
// CHECK-NOT: open_existential
// CHECK-NOT: witness_method
// CHECK-NOT: apply
// CHECK: integer_literal
// CHECK: return
@inline(never)
public func test_devirt_protocol_extension_method_invocation(_ c: C) -> Int32 {
  return callboo(c)
}


// Make sure that we are not crashing with an assertion due to specialization
// of methods with the Self return type as an argument.
// rdar://20868966
protocol Proto {
  func f() -> Self
}

class CC : Proto {
  func f() -> Self { return self }
}

func callDynamicSelfExistential(_ p: Proto) {
  p.f()
}

public func testSelfReturnType() {
  callDynamicSelfExistential(CC())
}


// Make sure that we are not crashing with an assertion due to specialization
// of methods with the Self return type.
// rdar://20955745.
protocol CP : class { func f() -> Self }
func callDynamicSelfClassExistential(_ cp: CP) { cp.f() }
class PP : CP {
  func f() -> Self { return self }
}

callDynamicSelfClassExistential(PP())

// Make sure we handle indirect conformances.
// rdar://24114020
protocol Base {
  var x: Int { get }
}
protocol Derived : Base {
}
struct SimpleBase : Derived {
  var x: Int
}
public func test24114020() -> Int {
  let base: Derived = SimpleBase(x: 1)
  return base.x
}

protocol StaticP {
  static var size: Int { get }
}
struct HasStatic<T> : StaticP {
  static var size: Int { return sizeof(T.self) }
}
public func testExMetatype() -> Int {
  let type: StaticP.Type = HasStatic<Int>.self
  return type.size
}

