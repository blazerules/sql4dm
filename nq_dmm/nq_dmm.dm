/*
    nq_dmm: DMM map loader for BYOND
    Copyright (C) 2016  NullQuery (http://www.byond.com/members/NullQuery)

    This program is part of the nq_utility library.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

var/nq_dmm/nq_dmm = new

/nq_dmm/proc/LoadMap(file, x_offset, y_offset, z_offset) LoadMapString(file2text(file), x_offset, y_offset, z_offset)
/nq_dmm/proc/SanitizeString(str) return replacetext(replacetext(str, new/regex("\\\\(?!\\\\)", "g"), ""), "\\\\", "\\")

/nq_dmm_object/var/name
/nq_dmm_object/var/path
/nq_dmm_object/var/list/variables
/nq_dmm_object/var/list/parameters

/nq_dmm_object/New(path, list/variables, list/parameters)
	src.path                                 = path
	src.variables                            = variables
	src.parameters                           = parameters
	src.name                                 = "new[path]([parameters ? parameters.Join(", ") : ""])[variables ? json_encode(variables) : ""]"

/nq_dmm_object/proc/Instantiate(turf/loc)
	var/list/L = new/list()
	L.Add(loc)
	if (parameters)                          L.Add(parameters)

	if (path == /area || CO.StartsWith("[path]", "/area/"))
		var/area/A                           = locate(path)

		if (!A)                              A = new path()

		if (A)                               A.contents.Add(loc)

		return A
	else
		var/atom/A                           = new path(arglist(L))

		if (variables)
			var/nq_dmm_object/obj
			for (var/key in variables)
				obj                          = variables[key]

				if (istype(obj))             A.vars[key] = obj.Instantiate(istype(obj.path, /atom/movable) ? null : A)
				else                         A.vars[key] = variables[key]

		return A

/nq_dmm/proc/ParseGroup(str)
	str                                      = str + ","

	var/list/L                               = new/list()
	var/regex/r                              = new("\\s*(.*?)\\s*(\[{,\])", "g")
	var/pos
	var/pos2
	var/list/parameters
	var/list/variables

	while (r.Find(str))
		if (r.group[1])
			if (r.group[2] == ",")           pos = r.next - 1
			else                             pos = CO.IndexAfterGroup(str, r.next - 1)

			parameters                       = null
			variables                        = ParseVariables(copytext(str, r.next, pos), ";")

			if (text2ascii(str, pos + 1) == text2ascii("("))
				pos2                         = pos + 1
				pos                          = CO.IndexAfterGroup(str, pos2)
				parameters                   = ParseVariables(copytext(str, pos2 + 1, pos), ",")
			else                             parameters = null

			L.Add(new/nq_dmm_object(text2path(r.group[1]), variables, parameters))

			r.next                           = pos + 1

	var/nq_dmm_object/turf

	for (var/nq_dmm_object/obj in L)
		if (obj.path == /turf || CO.StartsWith("[obj.path]", "/turf/")) turf = obj

	if (turf)
		var/type,icon,icon_state,dir,layer
		var/list/underlays

		for (var/nq_dmm_object/obj in L)
			if (obj != turf && (obj.path == /turf || CO.StartsWith("[obj.path]", "/turf/")))
				type                         = obj.path
				underlays                    = turf.variables && turf.variables["underlays"] ? turf.variables["underlays"] : new/list()

				if (obj.variables && ("underlays" in obj.variables))
					underlays.Add(obj.variables["underlays"])
				else if (initial(type:underlays))
					underlays.Add(initial(type:underlays))

				if (obj.variables && ("icon" in obj.variables))
					icon = obj.variables["icon"]
				else
					icon = initial(type:icon)

				if (obj.variables && ("icon_state" in obj.variables))
					icon_state = obj.variables["icon_state"]
				else
					icon_state = initial(type:icon_state)

				if (obj.variables && ("layer" in obj.variables))
					layer = obj.variables["layer"]
				else
					layer = initial(type:layer)

				if (obj.variables && ("dir" in obj.variables))
					dir = obj.variables["dir"]
				else
					dir = initial(type:dir)

				underlays.Insert(1, image(icon, null, icon_state, layer, dir))

				if (!turf.variables)         turf.variables = new/list()
				turf.variables["underlays"]  = underlays

	return L

/nq_dmm/proc/ParseVariables(str, splitter)
	if (str)
		var/list/L                           = new/list()
		var/list/tempL
		var/start_pos                        = 1
		var/end_pos

		do
			end_pos                          = CO.IndexAfterGroupChar(str, splitter, start_pos)

			tempL                            = ParseVariable(copytext(str, start_pos, max(end_pos - 1, 0)))

			if (tempL.len == 2)
				if (tempL[1])                L[tempL[1]] = tempL[2]
				else                         L.Add(tempL[2])

			start_pos                        = end_pos
		while (end_pos > 0)

		return L

/nq_dmm/proc/ParseVariable(str)
	var/list/L                               = new/list()
	var/regex/r                              = new("(\\s*(.*?)\\s*=)?\\s*(.*)")

	if (r.Find(str))
		L.Add(r.group[2])
		L.Add(ParseValue(r.group[3]))

	return L

/nq_dmm/proc/ParseValue(str)
	str                                      = CO.Trim(str)

	if      (str == "null")                  return null
	else if (CO.StartsWith(str, "\"") && CO.EndsWith(str, "\""))
		return SanitizeString(copytext(str, 2, length(str)))
	else if (CO.StartsWith(str, "new/") || CO.StartsWith(str, "new /"))
		var/list/L                           = ParseGroup(CO.Right(str, "new"))
		if (L && L.len)                      return L[1]
	else
		var/pos                              = CO.IndexOf(str, "(")

		if (pos)
			var/name                         = CO.Left("(")
			var/list/L                       = ParseVariables(CO.BackwardsLeft(CO.Right(str, "("), ")"), ",")

			if (name == "list")              return L
			else                             return null
		else                                 return text2num(str)

/nq_dmm/proc/LoadMapString(str, x_offset = 0, y_offset = 0, z_offset = 0)
	var/regex/r
	var/pos

	// Remove single-line comments.
	r                                        = new("^\\/\\/.*\\r?\\n?", "igm")
	str                                      = r.Replace(str, "")

	r                                        = new("\\s*\"(.*?)\"\\s*=\\s*\\(", "g")

	var/list/groups                          = new/list()
	var/key_length                           = 0

	while (r.Find(str))
		pos                                  = CO.IndexAfterGroup(str, r.next - 1)
		key_length                           = length(r.group[1])
		groups[r.group[1]]                   = ParseGroup(copytext(str, r.next, pos))
		r.next                               = pos

	r                                        = new("\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)\\s*=\\s*\\{\"\\s*(\[\\w\\W\n\]*)\"\\}", "g")
	r.next                                   = pos + 1

	var/x1,y1,z
	var/maxx,maxy
	var/list/rows
	var/y
	var/list/group

	while (r.Find(str))
		x1                                   = x_offset + text2num(r.group[1])
		y1                                   = y_offset + text2num(r.group[2])
		z                                    = z_offset + text2num(r.group[3])
		rows                                 = splittext(CO.Trim(r.group[4]), "\n")
		maxy                                 = y1 + rows.len - 1

		if (maxy > 0)
			maxx                             = x1 + (length(rows[1]) / key_length) - 1

			if (world.maxx < maxx)           world.maxx = maxx
			if (world.maxy < maxy)           world.maxy = maxy
			if (world.maxz < z)              world.maxz = z

			ASSERT(maxx == round(maxx))

			y = maxy
			for (var/row in rows)
				pos = 1
				for (var/x = x1 to maxx)
					group                    = groups[copytext(row, pos, pos + key_length)]

					if (group)
						for (var/nq_dmm_object/obj in group)
							obj.Instantiate(locate(x, y, z))

					pos                      = pos + key_length

				y--