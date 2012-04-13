#!/usr/local/bin/ruby -w

$TESTING = true

$: << 'lib'

require 'minitest/autorun'
require 'ruby2ruby'
require 'pt_testcase'
require 'fileutils'
require 'tmpdir'

class R2RTestCase < ParseTreeTestCase
  def self.previous key
    "ParseTree"
  end

  def self.generate_test klass, node, data, input_name, output_name
    output_name = data.has_key?('Ruby2Ruby') ? 'Ruby2Ruby' : 'Ruby'

    return if node.to_s =~ /19$/

    klass.class_eval <<-EOM
      def test_#{node}
        pt = #{data[input_name].inspect}
        rb = #{data[output_name].inspect}

        refute_nil pt, \"ParseTree for #{node} undefined\"
        refute_nil rb, \"Ruby for #{node} undefined\"

        assert_equal rb, @processor.process(pt)
      end
    EOM
  end
end

start = __LINE__

class TestRuby2Ruby < R2RTestCase
  def setup
    super
    @processor = Ruby2Ruby.new
  end

  def test_util_dthing_dregx
    inn = util_thingy(:dregx)
    inn.shift
    out = '/a"b#{(1 + 1)}c"d\/e/'
    exp = /a"b2c"d\/e/

    assert_equal exp, eval(out)

    assert_equal out[1..-2], @processor.util_dthing(:dregx, inn)
  end

  def test_util_dthing_dstr
    inn = util_thingy(:dstr)
    inn.shift
    out = '"a\"b#{(1 + 1)}c\"d/e"'
    exp = 'a"b2c"d/e'

    assert_equal exp, eval(out)

    assert_equal out[1..-2], @processor.util_dthing(:dstr, inn)
  end

  def test_util_dthing_dregx_bug?
    inn = s(:dregx, '[\/\"]', s(:evstr, s(:lit, 42)))
    inn.shift
    out = '/[\/\"]#{42}/'
    exp =  /[\/\"]42/

    assert_equal out[1..-2], @processor.util_dthing(:dregx, inn)
    assert_equal exp, eval(out)
  end

  def test_and_alias
    inn = s(:and, s(:true), s(:alias, s(:lit, :a), s(:lit, :b)))
    out = "true and (alias :a :b)"
    util_compare inn, out
  end

  def test_dregx_slash
    inn = util_thingy(:dregx)
    out = '/a"b#{(1 + 1)}c"d\/e/'
    util_compare inn, out, /a"b2c"d\/e/
  end

  def test_dstr_quote
    inn = util_thingy(:dstr)
    out = '"a\"b#{(1 + 1)}c\"d/e"'
    util_compare inn, out, 'a"b2c"d/e'
  end

  def test_dsym_quote
    inn = util_thingy(:dsym)
    out = ':"a\"b#{(1 + 1)}c\"d/e"'
    util_compare inn, out, :'a"b2c"d/e'
  end

  def test_lit_regexp_slash
    util_compare s(:lit, /blah\/blah/), '/blah\/blah/', /blah\/blah/
  end

  def test_call_self_index
    util_compare s(:call, nil, :[], s(:arglist, s(:lit, 42))), "self[42]"
  end

  def test_call_self_index_equals
    util_compare(s(:call, nil, :[]=, s(:arglist, s(:lit, 42), s(:lit, 24))),
                 "self[42] = 24")
  end

  def test_call_arglist_hash_first
    inn = s(:call, nil, :method,
            s(:arglist,
              s(:hash, s(:lit, :a), s(:lit, 1)),
              s(:call, nil, :b, s(:arglist))))
    out = "method({ :a => 1 }, b)"

    util_compare inn, out
  end

  def test_call_arglist_hash_first_last
    inn = s(:call, nil, :method,
            s(:arglist,
              s(:hash, s(:lit, :a), s(:lit, 1)),
              s(:call, nil, :b, s(:arglist)),
              s(:hash, s(:lit, :c), s(:lit, 1))))
    out = "method({ :a => 1 }, b, :c => 1)"

    util_compare inn, out
  end

  def test_call_arglist_hash_last
    inn = s(:call, nil, :method,
            s(:arglist,
              s(:call, nil, :b, s(:arglist)),
              s(:hash, s(:lit, :a), s(:lit, 1))))
    out = "method(b, :a => 1)"

    util_compare inn, out
  end

  def test_call_arglist_if
    inn = s(:call,
            s(:call, nil, :a, s(:arglist)),
            :+,
            s(:arglist,
              s(:if,
                s(:call, nil, :b, s(:arglist)),
                s(:call, nil, :c, s(:arglist)),
                s(:call, nil, :d, s(:arglist)))))

    out = "(a + (b ? (c) : (d)))"
    util_compare inn, out
  end

  def test_masgn_wtf
    inn = s(:block,
            s(:masgn,
              s(:array, s(:lasgn, :k), s(:lasgn, :v)),
              s(:array,
                s(:splat,
                  s(:call,
                    s(:call, nil, :line, s(:arglist)),
                    :split,
                    s(:arglist, s(:lit, /\=/), s(:lit, 2)))))),
            s(:attrasgn,
              s(:self),
              :[]=,
              s(:arglist, s(:lvar, :k),
                s(:call, s(:lvar, :v), :strip, s(:arglist)))))

    out = "k, v = *line.split(/\\=/, 2)\nself[k] = v.strip\n"

    util_compare inn, out
  end

  def test_masgn_splat_wtf
    inn = s(:masgn,
            s(:array, s(:lasgn, :k), s(:lasgn, :v)),
            s(:array,
              s(:splat,
                s(:call,
                  s(:call, nil, :line, s(:arglist)),
                  :split,
                  s(:arglist, s(:lit, /\=/), s(:lit, 2))))))
    out = 'k, v = *line.split(/\\=/, 2)'
    util_compare inn, out
  end

  def test_match3_asgn
    inn = s(:match3, s(:lit, //), s(:lasgn, :y, s(:call, nil, :x, s(:arglist))))
    out = "(y = x) =~ //"
    # "y = x =~ //", which matches on x and assigns to y (not what sexp says).
    util_compare inn, out
  end

  def test_splat_call
    inn = s(:call, nil, :x,
            s(:arglist,
              s(:splat,
                s(:call,
                  s(:call, nil, :line, s(:arglist)),
                  :split,
                  s(:arglist, s(:lit, /\=/), s(:lit, 2))))))

    out = 'x(*line.split(/\=/, 2))'
    util_compare inn, out
  end

  def test_resbody_block
    inn = s(:rescue,
            s(:call, nil, :x1, s(:arglist)),
            s(:resbody,
              s(:array),
              s(:block,
                s(:call, nil, :x2, s(:arglist)),
                s(:call, nil, :x3, s(:arglist)))))

    out = "begin\n  x1\nrescue\n  x2\n  x3\nend"
    util_compare inn, out
  end

  def test_resbody_short_with_begin_end
    # "begin; blah; rescue; []; end"
    inn = s(:rescue,
            s(:call, nil, :blah, s(:arglist)),
            s(:resbody, s(:array), s(:array)))
    out = "blah rescue []"
    util_compare inn, out
  end

  def test_regexp_options
    inn = s(:match3,
            s(:dregx,
              "abc",
              s(:evstr, s(:call, nil, :x, s(:arglist))),
              s(:str, "def"),
              4),
            s(:str, "a"))
    out = '"a" =~ /abc#{x}def/m'
    util_compare inn, out
  end

  def test_resbody_short_with_rescue_args
    inn = s(:rescue,
            s(:call, nil, :blah, s(:arglist)),
            s(:resbody, s(:array, s(:const, :A), s(:const, :B)), s(:array)))
    out = "begin\n  blah\nrescue A, B\n  []\nend"
    util_compare inn, out
  end

  def test_call_binary_call_with_hash_arg
    # if 42
    #   args << {:key => 24}
    # end

    inn = s(:if, s(:lit, 42),
            s(:call, s(:call, nil, :args, s(:arglist)),
              :<<,
              s(:arglist, s(:hash, s(:lit, :key), s(:lit, 24)))),
            nil)

    out = "(args << { :key => 24 }) if 42"

    util_compare inn, out
  end

  def test_if_empty
    inn = s(:if, s(:call, nil, :x, s(:arglist)), nil, nil)
    out = "if x then\n  # do nothing\nend"
    util_compare inn, out
  end

  def test_interpolation_and_escapes
    # log_entry = "  \e[#{message_color}m#{message}\e[0m   "
    inn = s(:lasgn, :log_entry,
            s(:dstr, "  \e[",
              s(:evstr, s(:call, nil, :message_color, s(:arglist))),
              s(:str, "m"),
              s(:evstr, s(:call, nil, :message, s(:arglist))),
              s(:str, "\e[0m   ")))
    out = "log_entry = \"  \e[#\{message_color}m#\{message}\e[0m   \""

    util_compare inn, out
  end

  def test_class_comments
    inn = s(:class, :Z, nil, s(:scope))
    inn.comments = "# x\n# y\n"
    out = "# x\n# y\nclass Z\nend"
    util_compare inn, out
  end

  def test_module_comments
    inn = s(:module, :Z, s(:scope))
    inn.comments = "# x\n# y\n"
    out = "# x\n# y\nmodule Z\nend"
    util_compare inn, out
  end

  def test_method_comments
    inn = s(:defn, :z, s(:args), s(:scope, s(:block, s(:nil))))
    inn.comments = "# x\n# y\n"
    out = "# x\n# y\ndef z\n  # do nothing\nend"
    util_compare inn, out
  end

  def test_basic_ensure
    inn = s(:ensure, s(:lit, 1), s(:lit, 2))
    out = "begin\n  1\nensure\n  2\nend"
    util_compare inn, out
  end

  def test_nested_ensure
    inn = s(:ensure, s(:lit, 1), s(:ensure, s(:lit, 2), s(:lit, 3)))
    out = "begin\n  1\nensure\n  begin\n    2\n  ensure\n    3\n  end\nend"
    util_compare inn, out
  end

  def test_nested_rescue
    inn = s(:ensure, s(:lit, 1), s(:rescue, s(:lit, 2), s(:resbody, s(:array), s(:lit, 3))))
    out = "begin\n  1\nensure\n  2 rescue 3\nend"
    util_compare inn, out
  end

  def test_nested_rescue_exception
    inn = s(:ensure, s(:lit, 1), s(:rescue, s(:lit, 2), s(:resbody, s(:array, s(:const, :Exception)), s(:lit, 3))))
    out = "begin\n  1\nensure\n  begin\n    2\n  rescue Exception\n    3\n  end\nend"
    util_compare inn, out
  end

  def test_nested_rescue_exception2
    inn = s(:ensure, s(:rescue, s(:lit, 2), s(:resbody, s(:array, s(:const, :Exception)), s(:lit, 3))), s(:lit, 1))
    out = "begin\n  2\nrescue Exception\n  3\nensure\n  1\nend"
    util_compare inn, out
  end

  def test_rescue_block
    inn = s(:rescue,
            s(:call, nil, :alpha, s(:arglist)),
            s(:resbody, s(:array),
              s(:block,
                s(:call, nil, :beta, s(:arglist)),
                s(:call, nil, :gamma, s(:arglist)))))
    out = "begin\n  alpha\nrescue\n  beta\n  gamma\nend"
    util_compare inn, out
  end

  def util_compare sexp, expected_ruby, expected_eval = nil
    assert_equal expected_ruby, @processor.process(sexp)
    assert_equal expected_eval, eval(expected_ruby) if expected_eval
  end

  def util_thingy(type)
    s(type,
      'a"b',
      s(:evstr, s(:call, s(:lit, 1), :+, s(:arglist, s(:lit, 1)))),
      s(:str, 'c"d/e'))
  end
end

####################
#         impl
#         old  new
#
# t  old    0    1
# e
# s
# t  new    2    3

tr2r = File.read(__FILE__).split(/\n/)[start+1..__LINE__-2].join("\n")
ir2r = File.read("lib/ruby2ruby.rb")

require 'ruby_parser'

def silent_eval ruby
  old, $-w = $-w, nil
  eval ruby
  $-w = old
end

def morph_and_eval src, from, to, processor
  new_src = processor.new.process(Ruby18Parser.new.process(src.sub(from, to)))
  silent_eval new_src
  new_src
end

____ = morph_and_eval tr2r, /TestRuby2Ruby/, 'TestRuby2Ruby2', Ruby2Ruby
ruby = morph_and_eval ir2r, /Ruby2Ruby/,     'Ruby2Ruby2',     Ruby2Ruby
____ = morph_and_eval ruby, /Ruby2Ruby2/,    'Ruby2Ruby3',     Ruby2Ruby2

class TestRuby2Ruby1 < TestRuby2Ruby
  def setup
    super
    @processor = Ruby2Ruby2.new
  end
end

class TestRuby2Ruby3 < TestRuby2Ruby2
  def setup
    super
    @processor = Ruby2Ruby2.new
  end
end

class TestRuby2Ruby4 < TestRuby2Ruby2
  def setup
    super
    @processor = Ruby2Ruby3.new
  end
end
