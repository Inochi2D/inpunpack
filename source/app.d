module app;
import stdio = std.stdio;
import std.file;
import std.path;
import std.exception;
import inochi2d.fmt.binfmt;
import imagefmt;
import std.format;
import std.json;
import std.bitmanip;
import std.range;
import commandr;

int main(string[] iargs) {
    Program program = new Program("inpunpack", "1.1");
    ProgramArgs args = program
        .summary("Pack and unpack Inochi2D INP and INX files")
        .author("Luna the Foxgirl")
        .add(
            new Command("unpack", "Unpack INP file")
                .add(new Argument("files", "Files to unpack").repeating())
                .add(new commandr.Flag("r", "raw", "Unpack without validating JSON"))
        )
        .add(
            new Command("pack", "Pack INP file")
                .add(new Argument("paths", "Paths/directories to unpack").repeating())
        )
        .parse(iargs);
    try {
        args.on("pack", (ProgramArgs args) {

            // Validate
            foreach(path; args.argAll("paths")) {
                enforce(exists(path), "%s does not exist!".format(path));
                enforce(isDir(path), "%s is not a directory!".format(path));
                enforce(exists(buildPath(path, "payload.json")), "%s has no payload!".format(path));
            }

            foreach(path; args.argAll("paths")) {
                pack(path);
            }

        }).on("unpack", (ProgramArgs args) {

            // Validate
            foreach(file; args.argAll("files")) {
                enforce(exists(file), "%s does not exist!".format(file));
                enforce(isFile(file), "%s is not a file!".format(file));
            }

            bool raw = args.hasFlag("raw");
            foreach(file; args.argAll("files")) {
                unpack(file, raw);
            }
        });
    } catch (Exception ex) {
        stdio.stderr.writeln(ex.msg);
        return -1;
    }
    return 0;
    

    // try {
    //     if (args.length == 1 || (args[1] == "c" && args.length != 3)) {
    //         stdio.writeln("inpunpack <c> FILE/FOLDER");
    //         return;
    //     }
    //     if (args[1] == "c") {
    //         pack(args[2]);
    //     } else {
    //         unpack(args[1]);
    //     }
    // } catch(Throwable t) {
    //     stdio.writeln(t.msg);
    // }
}

void unpack(string file, bool raw) {
    string outFolder = file.baseName.stripExtension;
    size_t bufferOffset = 0;
    ubyte[] buffer = cast(ubyte[])std.file.read(file);
    
    enforce(inVerifyMagicBytes(buffer), "Invalid data format for INP puppet");
    bufferOffset += 8; // Magic bytes are 8 bytes

    // Find the puppet data
    uint puppetDataLength;
    inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], puppetDataLength);

    // Make out dir
    if (!exists(outFolder)) mkdir(outFolder);

    // write the payload
    string jpayload = cast(string)buffer[bufferOffset..bufferOffset+=puppetDataLength];
    if (raw) write(buildPath(outFolder, "payload.json"), jpayload);
    else write(buildPath(outFolder, "payload.json"), parseJSON(jpayload).toPrettyString());

    // Enforce texture section existing
    enforce(inVerifySection(buffer[bufferOffset..bufferOffset+=8], TEX_SECTION), "Expected Texture Blob section, got nothing!");

    // Get amount of slots
    uint slotCount;
    inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], slotCount);
    foreach(i; 0..slotCount) {
        
        uint textureLength;
        inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], textureLength);
        ubyte typeTag = buffer[bufferOffset++];

        string textFileName = "tex_%s_%s.tex".format(i, typeTag);
        if (textureLength == 0) write(textFileName, []);
        else write(buildPath(outFolder, textFileName), buffer[bufferOffset..bufferOffset+=textureLength]);
    }

    if (buffer.length >= bufferOffset + 8 && inVerifySection(buffer[bufferOffset..bufferOffset+=8], EXT_SECTION)) {
        uint sectionCount;
        inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], sectionCount);

        foreach(section; 0..sectionCount) {

            // Get name of payload/vendor extended data
            uint sectionNameLength;
            inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], sectionNameLength);            
            string sectionName = cast(string)buffer[bufferOffset..bufferOffset+=sectionNameLength];

            // Get length of data
            uint payloadLength;
            inInterpretDataFromBuffer(buffer[bufferOffset..bufferOffset+=4], payloadLength);

            // Load the vendor JSON data in to the extData section of the puppet
            ubyte[] payload = buffer[bufferOffset..bufferOffset+=payloadLength];
            write(buildPath(outFolder, "ext_%s.bin".format(sectionName)), payload);
        }
    }
}

void pack(string folder) {
    enforce(exists(buildPath(folder, "payload.json")), "Payload not found in "~folder);
    auto app = appender!(ubyte[]);

    // Write the current used Inochi2D version to the version_ meta tag.
    string puppetJson = readText(buildPath(folder, "payload.json"));
    puppetJson = parseJSON(puppetJson).toString();

    app ~= MAGIC_BYTES;
    app ~= nativeToBigEndian(cast(uint)puppetJson.length)[0..4];
    app ~= cast(ubyte[])puppetJson;
    
    // Begin texture section
    app ~= TEX_SECTION;
    Texture[] textures = scanTextures(folder);
    app ~= nativeToBigEndian(cast(uint)textures.length)[0..4];
    foreach(texture; textures) {
        app ~= nativeToBigEndian(cast(uint)texture.data.length)[0..4];
        app ~= (texture.tag);
        app ~= (texture.data);
    }

    // Don't waste bytes on empty EXT data sections
    ubyte[][string] extData = scanExtData(folder);
    if (extData.length > 0) {
        // Begin extended section
        app ~= EXT_SECTION;
        app ~= nativeToBigEndian(cast(uint)extData.length)[0..4];

        foreach(name, payload; extData) {
            
            // Write payload name and its length
            app ~= nativeToBigEndian(cast(uint)name.length)[0..4];
            app ~= cast(ubyte[])name;

            // Write payload length and payload
            app ~= nativeToBigEndian(cast(uint)payload.length)[0..4];
            app ~= payload;

        }
    }

    // Write it out to file
    write(folder~".inp", app.data);
}

struct Texture {
    ubyte tag;
    ubyte[] data;
}

Texture[] scanTextures(string folder) {
    import std.conv : to;
    import std.string : split;
    uint highestTexCount;
    Texture[uint] textures;
    Texture[] out_;

    foreach(DirEntry e; dirEntries(folder, "tex_*", SpanMode.shallow, false)) {
        string[] s = split(e.name().baseName().stripExtension(), "_");
        uint texId = s[1].to!uint;
        ubyte texType = s[2].to!ubyte;
        if (s[1].to!uint > highestTexCount) highestTexCount = texId;

        textures[texId] = Texture(
            texType,
            cast(ubyte[])read(e.name())
        );
    }
    out_.length = highestTexCount+1;

    foreach(i, tex; textures) {
        out_[i] = tex;
    }
    return out_;
}

ubyte[][string] scanExtData(string folder) {
    import std.string : split, join;
    ubyte[][string] out_;
    foreach(DirEntry e; dirEntries(folder, "ext_*", SpanMode.shallow, false)) {
        string[] s = split(e.name().baseName().stripExtension(), "_");
        out_[s[1..$].join("_")] = cast(ubyte[])read(e.name());
    }
    return out_;
}