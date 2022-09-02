local function graphviz(code, filetype, bgcol, fgcol)
  return pandoc.pipe("dot", {
    "-T" .. filetype,
    "-Ncolor=" .. fgcol,
    "-Nfontcolor=" .. fgcol,
    "-Ecolor=" .. fgcol,
    "-Gbgcolor=" .. bgcol,
  }, code)
end

function CodeBlock(block)
  if block.classes[1] ~= "graphviz" then
    return nil
  end

  local success, svg_light_mode = pcall(graphviz, block.text, "svg", "#fafafa", "#444444")
  local success, svg_dark_mode = pcall(graphviz, block.text, "svg", "#222222", "#dddddd")

  return pandoc.RawBlock(
    "html",
    "<div class=\"light\">" .. svg_light_mode .. "</div>\n" ..
    "<div class=\"dark\">" .. svg_dark_mode .. "</div>"
  )
end
