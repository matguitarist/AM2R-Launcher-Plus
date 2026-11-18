using System.Linq;
using System.Text.Json;
var outPath = Environment.GetEnvironmentVariable("OUT");
var scripts = new HashSet<string>(Data.Scripts.Select(s => s.Name.Content));
var ext = new HashSet<string>(Data.Extensions.SelectMany(e => e.Files).SelectMany(f => f.Functions).Select(f => f.Name.Content));
var calls = new Dictionary<string, HashSet<string>>();
var vars = new Dictionary<string, HashSet<string>>();
foreach (var code in Data.Code) {
  if (code.Instructions == null) continue;
  foreach (var ins in code.Instructions) {
    if (ins.ValueFunction != null) {
      var n = ins.ValueFunction.Name.Content;
      if (!calls.ContainsKey(n)) calls[n] = new HashSet<string>();
      calls[n].Add(code.Name.Content);
    }
    if (ins.ValueVariable != null) {
      var n = ins.ValueVariable.Name.Content;
      if (!vars.ContainsKey(n)) vars[n] = new HashSet<string>();
      vars[n].Add(code.Name.Content);
    }
  }
}
var b = new UndertaleModLib.Compiler.BuiltinList(Data);
var builtinVars = new HashSet<string>(b.GlobalVars.Keys.Concat(b.GlobalArrayVars.Keys).Concat(b.InstanceVars.Keys).Concat(b.InstanceLimitedVars.Keys));
var result = new {
  game = Data.GeneralInfo.DisplayName.Content,
  bytecode = Data.GeneralInfo.BytecodeVersion,
  functions = calls.Where(kv => !scripts.Contains(kv.Key) && !ext.Contains(kv.Key))
                   .ToDictionary(kv => kv.Key, kv => kv.Value.OrderBy(x => x).ToList()),
  extensionFunctions = ext.OrderBy(x => x).ToList(),
  builtinVariables = vars.Where(kv => builtinVars.Contains(kv.Key))
                   .ToDictionary(kv => kv.Key, kv => kv.Value.OrderBy(x => x).ToList()),
};
File.WriteAllText(outPath, JsonSerializer.Serialize(result, new JsonSerializerOptions{WriteIndented=true}));
