require 'nokogiri'

class Html2Text
  attr_reader :doc

  def initialize(doc)
    @doc = doc
  end

  def self.convert(html)
    html = html.to_s
    html = fix_newlines(replace_entities(html))
    doc = Nokogiri::HTML(html)

    Html2Text.new(doc).convert
  end

  def self.fix_newlines(text)
    text.gsub("\r\n", "\n").gsub("\r", "\n")
  end

  def self.replace_entities(text)
    text.gsub("&nbsp;", " ").gsub("\u00a0", " ")
  end

  def convert
    output = process(doc)
    remove_leading_and_trailing_whitespace(output)
    remove_unnecessary_empty_lines(output)
    output.strip
  end

  def remove_leading_and_trailing_whitespace(text)
    # String#gsub! returns nil if no substition was performed, so these calls can't be chained.
    text.gsub!(/[ \t]*\n[ \t]*/im, "\n")
    text.gsub!(/ *\t */im, "\t")
  end

  def remove_unnecessary_empty_lines(text)
    text.gsub!(/\n\n\n*/im, "\n\n")
  end

  def trimmed_whitespace(text)
    # Replace whitespace characters with a space (equivalent to \s)
    text.gsub(/[\t\n\f\r ]+/im, " ")
  end

  def next_node_name(node)
    next_node = node.next_sibling
    while next_node != nil
      break if next_node.element?
      next_node = next_node.next_sibling
    end

    if next_node && next_node.element?
      next_node.name.downcase
    end
  end

  def process(root_node)
    # The original implementation used recursion to traverse the DOM, but that can cause stack
    # overflow in the case of incredibly deeply nested elements.  Instead, keep a local stack of
    # nodes to be processed, in order.
    #
    # We need to ensure that the pre-processing for a node is done before any of its children are
    # processed, and that the post-processing is done after all its children are processed.
    #
    # Original:
    #
    # - start at root node
    # - process node
    #   - emit prefix for node
    #   - recursivly process each child node
    #   - emit suffix for node
    #
    # New:
    #
    # - push element for root node onto the stack
    # - until stack is empty
    #   - pop top element from stack
    #   - emit prefix for node
    #   - push element to process suffix for node
    #   - push element for each child node

    output = ''
    elements_to_process = [{ type: :full, node: root_node }]

    until elements_to_process.empty?
      elem = elements_to_process.shift
      node = elem[:node]

      case elem[:type]
      when :full
        text, process_children = prefix_node(node)
        output << text
        elements_to_process.unshift({ type: :suffix, node: node })
        if process_children
          node.children.reverse.each do |child|
            elements_to_process.unshift({ type: :full, node: child })
          end
        end
      when :suffix
        output << suffix_node(node)
      end
    end

    output
  end

  def prefix_node(node)
    return [trimmed_whitespace(node.text), false] if node.text?
    return ["[image]", false] if node.name.downcase == "img"

    if ["style", "head", "title", "meta", "script"].include?(node.name.downcase)
      return ["", false]
    end

    output = case node.name.downcase
             when "hr"
               "---------------------------------------------------------------\n"

             when "h1", "h2", "h3", "h4", "h5", "h6", "ol", "ul"
               "\n"

             when "tr", "p", "div"
               "\n"

             when "td", "th"
               "\t"

             when "li"
               "- "

             else
               ""
             end
    return [output, true]
  end

  def suffix_node(node)
    output = case node.name.downcase
             when "h1", "h2", "h3", "h4", "h5", "h6"
               # add another line
               "\n"

             when "p", "br"
               "\n" if next_node_name(node) != "div"

             when "li"
               "\n"

             when "div"
               # add one line only if the next child isn't a div
               "\n" if next_node_name(node) != "div" && next_node_name(node) != nil
             end
    output ||= ""
    # Add an extra newline after links before headers
    if node.name.downcase == "a" && %w(h1 h2 h3 h4 h5 h6).include?(next_node_name(node))
      output << "\n"
    end

    output
  end
end
