// Compiles the GML file in $GML into a scratch copy of the game: into initroom's creation code, or,
// with $EVENT set to "<object>:DrawGUI", into that object's Draw GUI event (added if missing).
using UndertaleModLib.Compiler;
UndertaleCode code;
var target = Environment.GetEnvironmentVariable("EVENT");
if (string.IsNullOrEmpty(target)) {
    var room = Data.Rooms.ByName("initroom");
    code = UndertaleCode.CreateEmptyEntry(Data, "gml_RoomCC_initroom_enginecheck_Create");
    room.CreationCodeId = code;
} else {
    code = Data.GameObjects.ByName(target.Split(':')[0]).EventHandlerFor(EventType.Draw, 64u, Data);
}
var g = new CompileGroup(Data);
g.QueueCodeReplace(code, File.ReadAllText(Environment.GetEnvironmentVariable("GML")));
var r = g.Compile();
Console.WriteLine(r.Successful ? "COMPILED" : r.PrintAllErrors(true));
