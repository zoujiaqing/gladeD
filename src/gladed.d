// Robert Burner Schadek rburners@gmail.com LGPL3
import std.algorithm : map, uniq, sort;
import std.stdio : writeln, writefln, File;
import std.file : read;
import std.conv : to;
import std.array : appender, Appender;
import std.range : drop;
//import std.format : format, formattedWrite;
import std.format;
import std.uni : toUpper;
import std.getopt;

import std.experimental.logger;

import stack;
import dropuntil;
import xmltokenrange;

struct UnderscoreCap {
	string data;
	bool capNext;
	bool isFirst;

	@property dchar front() pure @safe {
		if(capNext || isFirst) {
			return std.uni.toUpper(data.front);
		} else {
			return data.front;
		}
	}

	@property bool empty() pure @safe nothrow {
		return data.empty;
	}

	@property void popFront() {
		if(!data.empty()) {
			isFirst = false;
			data.popFront();
			if(!data.empty() && data.front == '_') {
				capNext = true;
				data.popFront();
			} else {
				capNext = false;
			}
		}
	}
}

UnderscoreCap underscoreCap(IRange)(IRange i) {
	UnderscoreCap r;
	r.isFirst = true;
	r.data = i;
	return r;
}

unittest {
	auto s = "hello_world";
	auto sm = underscoreCap(s);
	assert(to!string(sm) == "HelloWorld", to!string(sm));
}

enum BinType {
	Invalid,
	Box,
	Notebook
}

struct Obj {
	BinType type;
	string obj;
	string cls;

	static Obj opCall(string o, string c) {
		Obj ret;
		ret.obj = o;
		ret.cls = c;
		switch(c) {
			case "GtkNotebook":
				ret.type = BinType.Notebook;
				break;
			default:
				ret.type = BinType.Box;
		}
		return ret;
	}

	string toAddFunction() pure @safe nothrow {
		final switch(this.type) {
			case BinType.Invalid: return "INVALID_BIN_TYPE";
			case BinType.Box: return "add";
			case BinType.Notebook: return "appendPage";
		}
	}

	string toName() pure @safe nothrow {
		if(this.obj == "placeholder") {
			return "new HBox()";
		} else {
			return this.obj;
		}
	}
}

void setupObjects(ORange,IRange)(ref ORange o, IRange i) {
	string curProperty;
	bool translateable;
	Stack!Obj objStack;
	objStack.push(Obj("this", "GtkWindow"));
	Stack!Obj childStack;

	foreach(it; i.drop(1)) {
		infoF(false, "%s %s %s", it.kind, it.kind == XmlTokenKind.Open || 
			it.kind == XmlTokenKind.Close || 
			it.kind == XmlTokenKind.OpenClose ?  it.name : "", 
			!objStack.empty ? objStack.top().obj : ""
		);

		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			infoF("%s %s", it.name, it["class"]);
			objStack.push(Obj(it["id"], it["class"]));
		} else if(it.kind == XmlTokenKind.Close && it.name == "object" ||
				it.kind == XmlTokenKind.OpenClose && it.name == "placeholder") {
			Obj ob;
			if(it.kind == XmlTokenKind.Close && it.name == "object") {
				infoF("%s %s", objStack.top().obj, objStack.top().cls);
				assert(!objStack.empty());
				ob = objStack.top();
				objStack.pop();
				if(ob.obj == "this") {
					break;
				}
			} else {
				info("Placeholder");
				ob = Obj("new Box()", "GtkBox");
			}
			assert(!objStack.empty());
			infoF("%s %s %u", objStack.top().obj, objStack.top().cls,
				childStack.length
			);
			if(objStack.top().cls == "GtkNotebook") {
				if(!childStack.empty()) {
					auto ob2 = childStack.top();
					childStack.pop();
					o.formattedWrite("\t\t%s.appendPage(%s, this.%s);\n\n", 
						objStack.top().obj, ob2.obj, ob.obj
					);
				} else {
					childStack.push(ob);
				}
			} else {
				assert(!objStack.empty());
				o.formattedWrite("\t\t%s.add(this.%s);\n\n", 
					objStack.top().obj, ob.obj
				);
			}
		} else if(it.kind == XmlTokenKind.Open && it.name == "property") {
			curProperty = it["name"];
		} else if(it.kind == XmlTokenKind.Text) {
			if(it.data == "False" || it.data == "True") {
				o.formattedWrite("\t\t%s.set%s(%s);\n", objStack.top().obj,
					underscoreCap(curProperty), it.data == "True" ? "true" :
					"false"
				);
			} else if(curProperty != "orientation") {
				o.formattedWrite("\t\t%s.set%s(\"%s\");\n", objStack.top().obj,
					underscoreCap(curProperty), it.data
				);
			}
		}
	}
}

string getBoxOrientation(IRange)(IRange i) {
	foreach(it; i) {
		infoF(it.kind == XmlTokenKind.Text, "%s %b", it.data, it.data ==
				"vertical");
		if(it.kind == XmlTokenKind.Text && it.data == "vertical") {
			info();
			return it.data;
		} else if(it.kind == XmlTokenKind.Text && it.data == "horizontal") {
			return it.data;
		}
	}
	assert(false);
}

void createClass(ORange,IRange)(ref ORange o, IRange i, string gladeString) {
	o.formattedWrite("\tstring __gladeString = `%s`;\n", gladeString);
	o.put("\tBuilder __superSecretBuilder;\n");
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			o.formattedWrite("\t%s %s;\n", it["class"][3 .. $], it["id"]);
		}
	}
	o.put("\n");
}

void createObjects(ORange,IRange)(ref ORange o, IRange i, bool isBox) {
	o.formattedWrite("\tthis() {\n");
	if(isBox) {
		o.put("\t\tsuper(Orientation.HORIZONTAL, 0);\n");
	} else {
		o.put("\t\tsuper(\"\");\n");
	}
	o.put("\t\t__superSecretBuilder = new Builder();\n");
	o.put("\t\t__superSecretBuilder.addFromString(__gladeString);\n");
	string box;
	int second = 0;
	bool firstBox = false;
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			logf("%s %s", it["class"], second);
			++second;
			assert(it.has("id"));
			assert(it.has("class"));
			o.formattedWrite("\t\tthis.%s = cast(%s)__superSecretBuilder." ~
				"getObject(\"%s\");\n", it["id"], it["class"][3 .. $], 
				it["id"], 
			);

			if(second == 1 && it.has("class") && it["class"] == "GtkBox") {
				box = it["id"];
				o.formattedWrite("\t\tthis.add(%s);\n", box);
				++second;
			} else if(second == 2) {
				box = it["id"];
				o.formattedWrite("\t\tthis.%s.reparent(this);\n", box);
				//o.formattedWrite("\t\tthis.add(%s);\n", box);
			}
		}
	}

	connectHandler(o, i);
	o.formattedWrite("\t\tshowAll();\n");
	o.formattedWrite("\t}\n");
}

bool hasToggle(string s) {
	return s == "GtkToggleButton" || s == "GtkCheckButton" || s ==
		"GtkMenuButton" || s == "GtkMenuButton";
}

bool hasActivate(string s) {
	return s == "GtkMenuItem" || s == "GtkImageMenuItem";
}

void connectHandler(ORange, IRange)(ref ORange o, IRange i) {
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			if(it.has("class") && it["class"] == "GtkButton") {
				o.formattedWrite("\t\tthis.%s.addOnClicked(&this.%sDele);\n",
					it["id"], it["id"]
				);
			} else if(it.has("class") && hasToggle(it["class"])) {
				o.formattedWrite("\t\tthis.%s.addOnToggle(&this.%sDele);\n",
					it["id"], it["id"]
				);
			} else if(it.has("class") && hasActivate(it["class"])) {
				o.formattedWrite("\t\tthis.%s.addOnActivate(&this.%sDele);\n",
					it["id"], it["id"]
				);
			}
		}
	}
}

string processArgType(string arg) {
	if(arg == "ImageMenuItem") {
		return "MenuItem";
	} else {
		return arg;
	}
}

void createOnClickHandler(ORange, IRange)(ref ORange o, IRange i) {
	foreach(it; i) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			if(it.has("class") && 
					(it["class"] == "GtkButton" || 
					 hasToggle(it["class"]) ||
					 hasActivate(it["class"])))
			{
				o.formattedWrite(
					"\n\tvoid %sDele(%s sig) {\n\t\t%sHandler(sig);\n\t}\n",
					it["id"], processArgType(it["class"][3 .. $]), it["id"]
				);

				o.formattedWrite(
					"\n\tvoid %sHandler(%s sig) {\n\t\t" ~ 
					"writeln(\"%sHandlerStub\");\n\t}\n",
					it["id"], processArgType(it["class"][3 .. $]), it["id"], 
					it["id"]
				);
			}
		}
	}
}

void main(string[] args) {
	string helpmsg = "gladeD transforms glade files into D Source files that "
		"make gtkd fun to use. Properly not all glade features will work." ~
		"Dummy onClickHandler will be created for everything I know about." ~
		"Check the example for, well an example.";

	string moduleName = "somemodule";
	string className = "SomeClass";
	string fileName = "";
	string output = "somemodule";
	LogLevel ll = LogLevel.fatal;
	auto rslt = getopt(args,
		"input|i", "The glade file you want to transform. The inputfile must" ~
		" be a valid glade file. Errors in the glade file will not be " ~
		"detacted.", 
			&fileName,
		"output|o", "The file to write the resulting module to.", &output,
		"classname|c", "The name of the resulting class.", &className,
		"modulename|m", "The module name of the resulting file.", &moduleName,
		"logLevel|l", "This option controles the LogLevel of the program. "
		~ "See std.logger for more information.", &ll);

	if(rslt.helpWanted) {
		defaultGetoptPrinter(helpmsg, rslt.options);
	}

	if(fileName.empty) {
		return;
	}

	globalLogLevel = ll;
		
	string input = cast(string)read(fileName);
	auto tokenRange = input.xmlTokenRange();
	auto payLoad = tokenRange.dropUntil!(a => a.kind == XmlTokenKind.Open && 
		a.name == "object" && a.has("class") && 
		(a["class"] == "GtkWindow" || a["class"] == "GtkBox")
	);

	bool isBox = payLoad.front["class"] == "GtkBox";

	XmlToken clsType;
	auto elem = appender!(XmlToken[])();
	clsType = payLoad.front;
	foreach(it; payLoad.drop(1)) {
		if(it.kind == XmlTokenKind.Open && it.name == "object") {
			elem.put(it);
		}
	}

	foreach(ref XmlToken it; elem.data()) {
		assert(it.has("id"));
		assert(it.has("class"));
		tracef("%s %s %s", it.name, it["class"], it["id"]);
	}

	trace(output);

	auto of = File(output, "w");
	auto ofr = of.lockingTextWriter();

	ofr.formattedWrite("module %s;\n\n", moduleName);
	trace("After module name");

	auto names = elem.data.map!(a => a["class"]);
	auto usedTypes = names.array.sort.uniq;
	foreach(it; usedTypes) {
		ofr.formattedWrite("public import gtk.%s;\n", it[3 .. $]);
	}
	ofr.formattedWrite("import gtk.%s;\n", clsType["class"][3 .. $]);
	ofr.put("import gtk.Builder;\n");
	ofr.put("import std.stdio;\n");

	tracef("%u ", clsType.attributes.length);

	ofr.formattedWrite("\nabstract class %s : %s {\n", className,
		clsType["class"][3 .. $]
	);

	trace("Before create classes");
	createClass(ofr, payLoad, input);
	createObjects(ofr, payLoad, isBox);
	createOnClickHandler(ofr, payLoad);
	ofr.formattedWrite("}\n");
}
