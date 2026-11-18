import json, re, sys
src = sys.argv[1]; d = json.load(open(sys.argv[2]))
c = open(src + "/vm_builtins.c").read()
impl = set(re.findall(r'VM_registerBuiltin\(ctx,\s*"([^"]+)"', c))
impl |= set(re.findall(r'\{"([a-z0-9_]+)",\s*"[A-Za-z0-9_]+",\s*builtin_', c))
# stubs: macro-defined and logStubbedFunction inside functions
full_stub = set(re.findall(r'STUB_RETURN_\w+\((\w+)', c))
maybe_stub = set(re.findall(r'logStubbedFunction\(ctx,\s*"([^"]+)"', c)) - full_stub
# builtin variable table
vt = set(re.findall(r'\{\s*"([a-z0-9_]+)"\s*,\s*BUILTIN_VAR_', c))
fn = d["functions"]; bv = d["builtinVariables"]
print("game", d["game"], "bytecode", d["bytecode"])
print("builtin functions called:", len(fn), "| builtin vars used:", len(bv), "| impl:", len(impl), "| var table:", len(vt))
def show(title, names, src):
    print(f"\n## {title} ({len(names)})")
    for n in sorted(names, key=lambda n: -len(src[n])):
        callers = src[n]; print(f"{n}  [{len(callers)} code] e.g. {', '.join(callers[:3])}")
show("MISSING functions", [n for n in fn if n not in impl], fn)
show("STUB functions (return a fixed value)", [n for n in fn if n in impl and n in full_stub], fn)
show("PARTIAL (may fall back to a stub)", [n for n in fn if n in impl and n in maybe_stub], fn)
show("MISSING builtin variables", [n for n in bv if n not in vt], bv)
print("\nextension functions:", d["extensionFunctions"])
