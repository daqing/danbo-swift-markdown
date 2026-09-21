//
//  Lexer.swift
//  swift-markdown
//

public enum TokenType: Equatable {
    case txt
    case newline
    case tab
    case h1
    case h2
    case bold
    case tilde
    case inlineCode
    case codeBlock
    case number
    case dash
    case eof
    case unknown
}

public struct Token {
    public let type: TokenType
    public let start: Int
    public let value: String

    public init(type: TokenType, start: Int, value: String) {
        self.type = type
        self.start = start
        self.value = value
    }
}

public class Lexer {
  public let content: String
  public private(set) var pos: String.Index
  public private(set) var readPos: String.Index
  public private(set) var idx: Int
  public private(set) var ch: Character?

  public init(content: String) {
    self.content = content
    self.readPos = self.content.startIndex
    self.pos = self.content.startIndex
    self.idx = -1
    self.ch = nil

    self.readChar()
  }
}

extension Lexer {
  public func readChar() {
    if self.readPos >= self.content.endIndex {
      self.ch = nil

      return
    } else {
      self.ch = self.content[self.readPos]
    }

    self.pos = self.readPos
    self.readPos = self.content.index(after: self.readPos)
    self.idx += 1
  }

  public func peekChar() -> Character? {
    if self.readPos >= self.content.endIndex {
      return nil
    } else {
      return self.content[self.readPos]
    }
  }

  public func readString() -> String? {
    let pos = self.pos

    while let ch = self.ch, isLetter(ch: ch) {
      self.readChar()
    }

    guard let _ = self.ch else {
      return nil
    }

    return String(self.content[pos..<self.pos])
  }

  public func readNumber() -> String? {
    let pos = self.pos

    while let ch = self.ch, isNumber(ch: ch) {
      self.readChar()
    }

    guard let _ = self.ch else {
      return nil
    }

    return String(self.content[pos..<self.pos])
  }

  public func nextToken() -> Token {
    guard let ch = self.ch else {
      return Token(type: .eof, start: self.idx, value: "")
    }

    let idx = self.idx

    switch ch {
      case "\t":
        self.readChar()
        return Token(type: .tab, start: idx, value: "\t")
      case "#":
        if let p = self.peekChar() {
          self.readChar()

          if p == "#" {
            // h2
            self.readChar()

            return Token(type: .h2, start: idx, value: "##")
          } else {
            // h1
            return Token(type: .h1, start: idx, value: "#")
          }
        }
      case "-":
        self.readChar()
        return Token(type: .dash, start: idx, value: "-")
      case "*":
        if let p = self.peekChar() {
          if p == "*" {
            self.readChar()
            self.readChar()
            return Token(type: .bold, start: idx, value: "**")
          }
        }

        self.readChar()
        return Token(type: .txt, start: idx, value: "*")
      case "~":
        if let p = self.peekChar() {
          if p == "~" {
            self.readChar()
            self.readChar()
            return Token(type: .tilde, start: idx, value: "~~")
          }
        }

        self.readChar()
        return Token(type: .txt, start: idx, value: "~")
      case "`":
        self.readChar()
        return Token(type: .inlineCode, start: idx, value: "`")
      case "\n":
        self.readChar()
        return Token(type: .newline, start: idx, value: "\n")
      default:
        if isNumber(ch: ch) {
          if let n = self.readNumber() {
            if let ch = self.ch {
              if ch == "." {
                self.readChar()
              }
            }

            return Token(type: .number,  start: idx, value: n)
          }
        }

        if let str = self.readString() {
          return Token(type: .txt, start: idx, value: str)
        }
    }

    return Token(type: .unknown, start: idx, value: String(ch))
  }
}

func isNumber(ch: Character) -> Bool {
  return ch >= "0" && ch <= "9"
}

func isLetter(ch: Character) -> Bool {
  return ch != "`" && ch != "*" && ch != "~" && ch != "#" && ch != "\n"
}

public protocol Row {
    var token: Token { get }
    var text: String { get }
}

public class TextRow: Row, CustomStringConvertible {
    public let token: Token
    public let text: String

    public init(token: Token, text: String) {
        self.token = token
        self.text = text
    }

    public var txtDesc: String {
        if self.text == "\n" {
            return "newline"
        }

        return self.text
    }

    public var description: String {
        return "(\(self.token), [\(self.txtDesc)])"
    }
}

public class Parser {
  public let lexer: Lexer
  public private(set) var curToken: Token
  public private(set) var peekToken: Token

  public init(lexer: Lexer) {
    self.lexer = lexer
    self.curToken = self.lexer.nextToken()
    self.peekToken = self.lexer.nextToken()
  }

  public func nextToken() {
    self.curToken = self.peekToken
    self.peekToken = self.lexer.nextToken()
  }

  public func curTokenIs(_ type: TokenType) -> Bool {
    return self.curToken.type == type
  }

  public func peekTokenIs(_ type: TokenType) -> Bool {
    return self.peekToken.type == type
  }

  public func parse() -> [Row] {
    var rows: [Row] = []

    while !self.curTokenIs(.eof) {
      if let row = self.parseRow() {
        rows.append(row)
      }

      self.nextToken()
    }

    return rows
  }

  public func parseRow() -> Row? {
    switch self.curToken.type {
      case .txt:
        let row = TextRow(token: self.curToken, text: self.curToken.value)

        if self.peekTokenIs(.newline) {
          self.nextToken()
        }

        return row
      case .newline:
        return TextRow(token: self.curToken, text: "\n")
      case .h1:
        return self.parseH1()
      case .h2:
        return self.parseH2()
      case .bold:
        return self.parseBold()
      case .tilde:
        return self.parseTilde()
      case .inlineCode:
        return self.parseInlineCode()
      case .codeBlock:
        // skip for now
        return nil
      case .number:
        return self.parseNumberRow()
      case .dash:
        return self.parseDashRow()
      default:
        break
    }

    return nil
  }

  public func parseH1() -> Row? {
    return self.parseElement(ending: .newline)
  }

  public func parseH2() -> Row? {
    return self.parseElement(ending: .newline)
  }

  public func parseBold() -> Row? {
    return self.parseElement(ending: .bold)
  }

  public func parseTilde() -> Row? {
    return self.parseElement(ending: .tilde)
  }

  public func parseInlineCode() -> Row? {
    return self.parseElement(ending: .inlineCode)
  }

  public func parseNumberRow() -> Row? {
    return self.parseElement(ending: .newline)
  }

  public func parseDashRow() -> Row? {
    if self.peekTokenIs(.dash) {
      // check for line separator
      self.nextToken()

      if self.peekTokenIs(.dash) {
        self.nextToken()

        if self.peekTokenIs(.newline) {
          self.nextToken()
          return TextRow(token: Token(type: .txt, start: self.lexer.idx - 3, value: "---"), text: "---")
        }
      }
    }

    return self.parseElement(ending: .newline)
  }

  public func parseElement(ending: TokenType) -> Row? {
      if self.peekTokenIs(.txt) {
        let tok = self.curToken
        self.nextToken()

        if self.peekTokenIs(ending) {
          let row = TextRow(token: tok, text: self.curToken.value)
          self.nextToken()

          return row
        }

      }

      let row = TextRow(token: self.curToken, text: self.curToken.value)

      if self.peekTokenIs(ending) {
        self.nextToken()
      }

      return row
  }
}
