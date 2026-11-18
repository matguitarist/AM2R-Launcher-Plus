using UndertaleModLib.Compiler;
var room = Data.Rooms.ByName("initroom");
var code = UndertaleCode.CreateEmptyEntry(Data, "gml_RoomCC_initroom_enginecheck_Create");
room.CreationCodeId = code;
var g = new CompileGroup(Data);
g.QueueCodeReplace(code, File.ReadAllText(Environment.GetEnvironmentVariable("GML")));
var r = g.Compile();
Console.WriteLine(r.Successful ? "COMPILED" : r.PrintAllErrors(true));
