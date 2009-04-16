
--- fs operations implemented with third-party tools for Windows platform abstractions.
-- Download http://unxutils.sourceforge.net/ for Windows GNU utilities
-- used by this module.
module("luarocks.fs.win32.tools", package.seeall)

local fs = require("luarocks.fs")

local function command_at(directory, cmd)
   local drive = directory:match("^([A-Za-z]:)")
   cmd = "cd " .. fs.Q(directory) .. " & " .. cmd
   if drive then
      cmd = drive .. " & " .. cmd
   end
   return cmd
end

--- Test for existance of a file.
-- @param file string: filename to test
-- @return boolean: true if file exists, false otherwise.
function exists(file)
   assert(file)
   return fs.execute("if not exist " .. fs.Q(file) ..
                     " invalidcommandname 2>NUL 1>NUL")
end

--- Test is pathname is a directory.
-- @param file string: pathname to test
-- @return boolean: true if it is a directory, false otherwise.
function is_dir(file)
   assert(file)
   return fs.execute("chdir /D " .. fs.Q(file) .. " 2>NUL 1>NUL")
end

--- Run the given command.
-- The command is executed in the current directory in the dir stack.
-- @param cmd string: No quoting/escaping is applied to the command.
-- @return boolean: true if command succeeds (status code 0), false
-- otherwise.
function execute_string(cmd)
   if os.execute(command_at(fs.current_dir(), cmd)) == 0 then
      return true
   else
      return false
   end
end

--- Test is pathname is a regular file.
-- @param file string: pathname to test
-- @return boolean: true if it is a regular file, false otherwise.
function is_dir(file)
   assert(file)
   return fs.execute("test -d" .. fs.Q(file) .. " 2>NUL 1>NUL")
end

--- Create a directory if it does not already exist.
-- If any of the higher levels in the path name does not exist
-- too, they are created as well.
-- @param d string: pathname of directory to create.
-- @return boolean: true on success, false on failure.
function make_dir(d)
   assert(d)
   fs.execute("mkdir "..fs.Q(d).." 1> NUL 2> NUL")
   return 1
end

--- Remove a directory if it is empty.
-- Does not return errors (for example, if directory is not empty or
-- if already does not exist)
-- @param d string: pathname of directory to remove.
function remove_dir_if_empty(d)
   assert(d)
   fs.execute_string("rmdir "..fs.Q(d).." 1> NUL 2> NUL")
end

--- Copy a file.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @return boolean or (boolean, string): true on success, false on failure,
-- plus an error message.
function copy(src, dest)
   assert(src and dest)
   if dest:match("[/\\]$") then dest = dest:sub(1, -2) end
   if fs.execute("cp", src, dest) then
      return true
   else
      return false, "Failed copying "..src.." to "..dest
   end
end

--- Recursively copy the contents of a directory.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @return boolean or (boolean, string): true on success, false on failure,
-- plus an error message.
function copy_contents(src, dest)
   assert(src and dest)
   if fs.execute_string("cp -a "..src.."\\*.* "..fs.Q(dest).." 1> NUL 2> NUL") then
      return true
   else
      return false, "Failed copying "..src.." to "..dest
   end
end

--- Delete a file or a directory and all its contents.
-- For safety, this only accepts absolute paths.
-- @param arg string: Pathname of source
-- @return boolean: true on success, false on failure.
function delete(arg)
   assert(arg)
   assert(arg:match("^[\a-zA-Z]?:?[\\/]"))
   fs.execute("chmod a+rw -R ", arg)
   return fs.execute_string("rm -rf " .. fs.Q(arg) .. " 1> NUL 2> NUL")
end

--- List the contents of a directory. 
-- @param at string or nil: directory to list (will be the current
-- directory if none is given).
-- @return table: an array of strings with the filenames representing
-- the contents of a directory.
function list_dir(at)
   assert(type(at) == "string" or not at)
   if not at then
      at = fs.current_dir()
   end
   if not fs.is_dir(at) then
      return {}
   end
   local result = {}
   local pipe = io.popen(command_at(at, "ls"))
   for file in pipe:lines() do
      table.insert(result, file)
   end
   pipe:close()

   return result
end

--- Recursively scan the contents of a directory. 
-- @param at string or nil: directory to scan (will be the current
-- directory if none is given).
-- @return table: an array of strings with the filenames representing
-- the contents of a directory. Paths are returned with forward slashes.
function find(at)
   assert(type(at) == "string" or not at)
   if not at then
      at = fs.current_dir()
   end
   if not fs.is_dir(at) then
      return {}
   end
   local result = {}
   local pipe = io.popen(command_at(at, "find 2> NUL")) 
   for file in pipe:lines() do
      -- Windows find is a bit different
      if file:sub(1,2)==".\\" then file=file:sub(3) end
      if file ~= "." then
         table.insert(result, (file:gsub("\\", "/")))
      end
   end
   return result
end

--- Download a remote file.
-- @param url string: URL to be fetched.
-- @param filename string or nil: this function attempts to detect the
-- resulting local filename of the remote file as the basename of the URL;
-- if that is not correct (due to a redirection, for example), the local
-- filename can be given explicitly as this second argument.
-- @return boolean: true on success, false on failure.
function download(url, filename)
   assert(type(url) == "string")
   assert(type(filename) == "string" or not filename)
   local wget_cmd = "wget --user-agent="..cfg.user_agent.." --quiet --continue "

   if filename then   
      return fs.execute(wget_cmd.." --output-document ", filename, url)
   else
      return fs.execute(wget_cmd, url)
   end
end

--- Uncompress gzip file.
-- @param archive string: Filename of archive.
-- @return boolean : success status
local function gunzip(archive)
   local cmd = fs.execute("gunzip -h 1>NUL 2>NUL") and 'gunzip' or
               fs.execute("gzip   -h 1>NUL 2>NUL") and 'gzip -d'
   local ok = fs.execute(cmd, archive)
   return ok
end

--- Unpack an archive.
-- Extract the contents of an archive, detecting its format by
-- filename extension.
-- @param archive string: Filename of archive.
-- @return boolean or (boolean, string): true on success, false and an error message on failure.
function unpack_archive(archive)
   assert(type(archive) == "string")
   
   local ok
   if archive:match("%.tar%.gz$") then
      ok = gunzip(archive)
      if ok then
         ok = fs.execute("tar -xf ", strip_extension(archive))
      end
   elseif archive:match("%.tgz$") then
      ok = gunzip(archive)
      if ok then
         ok = fs.execute("tar -xf ", strip_extension(archive)..".tar")
      end
   elseif archive:match("%.tar%.bz2$") then
      ok = fs.execute("bunzip2 ", archive)
      if ok then
         ok = fs.execute("tar -xf ", strip_extension(archive))
      end
   elseif archive:match("%.zip$") then
      ok = fs.execute("unzip ", archive)
   elseif archive:match("%.lua$") or archive:match("%.c$") then
      -- Ignore .lua and .c files; they don't need to be extracted.
      return true
   else
      local ext = archive:match(".*(%..*)")
      return false, "Unrecognized filename extension "..(ext or "")
   end
   if not ok then
      return false, "Failed extracting "..archive
   end
   return true
end
