<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:local="local"
  exclude-result-prefixes="#all" version="2.0">
  
  <!-- =================================================================================
   | An XSLT stylesheet that reads an OJS "reference" locale file (en_US), and either: |
   |  -creates an aligned version of a corresponding target locale file, if present    |
   |  -creates a corresponding locale file with empty entries (configurable), aligned  | 
   |   with the reference translation                                                  |
   | This works for both <locale> and <email_texts> files                              |
   | Running this script minimally requires following input:                           |
   |  -$reference.locale.uri: a URI to a local file with the reference locale (en_US)  |
   |   (if absent, the URI of the input document is used)                              |
   |  -$target.locale.abbrev: the code for the target locale                           |
   |   (necessary to construct the output file URI)                                    |
   ================================================================================== -->
  
  <!-- 
    @indent="no": just copy original ws, so no need to bother/interfere 
    @cdata-section-elements: a list of elements whose text() nodes will be serialized as CDATA sections
  -->
  <xsl:output method="xml" indent="no" cdata-section-elements="message-cdata body"/>

  <!-- ======================== -->
  <!-- PARAMETERS AND VARIABLES -->
  <!-- ======================== -->
    
  <!-- URI of reference locale file (defaults to URI of source document) -->
  <xsl:param name="reference.locale.uri" select="document-uri()" as="xs:string"/>
  <!-- URI of corresponding target locale file -->
  <xsl:param name="target.locale.uri" select="replace($reference.locale.uri, concat('/', $reference.locale.abbrev, '/'), concat('/', $target.locale.abbrev, '/'))" as="xs:string"/>
  <!-- URI for aligned version of target locale file -->
  <xsl:param name="output.uri" select="replace($target.locale.uri, '(.*)(\.[^./]+)$', '$1-aligned$2')" as="xs:string"/>
  
  <!-- reference locale identifier -->
  <xsl:param name="reference.locale.abbrev" as="xs:string"/>
  <!-- target locale identifier -->
  <xsl:param name="target.locale.abbrev" as="xs:string"/>
  <!-- target locale name -->
  <xsl:param name="target.locale.name" as="xs:string"/>
  
  <!-- switch: should empty entries be created for missing entries in the target locale? -->
  <xsl:param name="create.empty.entries" select="true()" as="xs:boolean"/>
  
  <xsl:variable name="reference.locale.doc" select="if (doc-available($reference.locale.uri)) then doc($reference.locale.uri) else ()"/>
  <xsl:variable name="target.locale.doc" select="if (doc-available($target.locale.uri)) then doc($target.locale.uri) else ()"/>
  
  <!-- lookup table for locale keys -->
  <xsl:key name="locale.entries" match="*" use="@key"/>
  
  <!-- =================== -->
  <!-- DOCUMENT PROCESSING -->  
  <!-- =================== -->
  
  <!-- create aligned target locale in new result document with name suffix -->
  <xsl:template match="/">
    <xsl:result-document href="{$output.uri}">
      <xsl:call-template name="locale.align"/>      
    </xsl:result-document>
  </xsl:template>
    
  <!-- locale: 
         -create new locale element for target locale
         -align existing entries and group orphans
  -->
  <xsl:template match="locale">
    <xsl:variable name="reference.locale" select="$reference.locale.doc/locale"/>
    <xsl:variable name="target.locale" select="$target.locale.doc/locale"/>
    <xsl:variable name="target.locale.orphan.entries" select="$target.locale/message[not(key('locale.entries', @key, $reference.locale.doc)[self::locale])]"/>
    <xsl:text>&#xa;</xsl:text>
    <locale name="{($target.locale.doc/locale/@name,$target.locale.abbrev)[normalize-space()][1]}" full_name="{($target.locale.doc/locale/@full_name,$target.locale.name)[normalize-space()][1]}">
      <xsl:call-template name="locale.process">
        <xsl:with-param name="reference.locale" select="$reference.locale"/>
        <xsl:with-param name="target.locale.orphan.entries" select="$target.locale.orphan.entries"/>
      </xsl:call-template>
      <xsl:text>&#xa;</xsl:text>
    </locale>
  </xsl:template>
  
  <!-- locale: 
         -create new email_texts element for target locale
         -align existing entries and group orphans
  -->
  <xsl:template match="email_texts">
    <xsl:variable name="reference.locale" select="$reference.locale.doc/email_texts"/>
    <xsl:variable name="target.locale" select="$target.locale.doc/email_texts"/>
    <xsl:variable name="target.locale.orphan.entries" select="$target.locale/email_text[not(key('locale.entries', @key, $reference.locale.doc)[self::email_text])]"/>
    <xsl:value-of select="local:generate.indent($reference.locale)"/>
    <xsl:text>&#xa;</xsl:text>
    <email_texts locale="{($target.locale.doc/email_texts/@locale,$target.locale.abbrev)[normalize-space()][1]}">
      <xsl:call-template name="locale.process">
        <xsl:with-param name="reference.locale" select="$reference.locale"/>
        <xsl:with-param name="target.locale.orphan.entries" select="$target.locale.orphan.entries"/>
      </xsl:call-template>
      <xsl:text>&#xa;</xsl:text>
    </email_texts>
  </xsl:template>

  <!-- message -->
  <xsl:template match="message">
    <xsl:param name="indent" tunnel="yes"/>    
    <xsl:variable name="target.locale.entry" select="if ($target.locale.doc) then key('locale.entries', @key, $target.locale.doc)[self::message](:[normalize-space()]:) else ()"/>
    <xsl:choose>
      <!-- if a corresponding target locale entry is found, basically copy that -->
      <xsl:when test="$target.locale.entry">
        <xsl:for-each select="$target.locale.entry[1]">
          <xsl:if test="$indent">
            <xsl:value-of select="local:generate.indent(.)"/>
          </xsl:if>
          <!-- specific processing: in order to preserve (selective) CDATA sections in OJS locale files, output <message-cdata> when <message> contains reserved XML character references -->
          <xsl:choose>
            <xsl:when test="matches(., '&lt;|&gt;|&amp;')">
              <!-- NOTE: <message-cdata> must later on manually be normalized to <message> -->
              <message-cdata key="{@key}">
                <xsl:apply-templates select="node()"/>
              </message-cdata>
            </xsl:when>
            <xsl:otherwise>
              <xsl:copy-of select="."/>            
            </xsl:otherwise>
          </xsl:choose>        
        </xsl:for-each>
      </xsl:when>
      <!-- if no corresponding target locale entry is found, create an emptied copy of the reference entry (if this has been switched on in $create.empty.entries) -->
      <xsl:otherwise>
        <xsl:if test="$create.empty.entries">
          <xsl:apply-templates select="." mode="drop.text"/>
        </xsl:if>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="email_text">
    <xsl:param name="indent" tunnel="yes"/>    
    <xsl:variable name="target.locale.entry" select="if ($target.locale.doc) then key('locale.entries', @key, $target.locale.doc)[self::email_text](:[normalize-space()]:) else ()"/>
    <xsl:choose>
      <!-- if a corresponding target locale entry is found, basically copy that -->
      <xsl:when test="$target.locale.entry">
        <xsl:if test="$indent">
          <xsl:value-of select="local:generate.indent(.)"/>
        </xsl:if>
        <xsl:copy-of select="$target.locale.entry[1]"/>
      </xsl:when>
      <!-- if no corresponding target locale entry is found, create an emptied copy of the reference entry (if this has been switched on in $create.empty.entries) -->
      <xsl:otherwise>
        <xsl:if test="$create.empty.entries">
          <xsl:apply-templates select="." mode="drop.text"/>
        </xsl:if>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <!-- default: identity copy -->
  <xsl:template match="@*|node()" mode="#all">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <!-- drop.text mode: don't copy text() -->
  <xsl:template match="text()[normalize-space()]" mode="drop.text" priority="1"/>
  
  <!-- ============================= -->
  <!-- NAMED TEMPLATES AND FUNCTIONS -->
  <!-- ============================= -->
  
  <!-- first determine whether target locale exists:
        -if so: copy all existing comments etc. from target locale
        -if not: copy all existing comments etc. from reference locale
  -->
  <xsl:template name="locale.align">
    <xsl:variable name="locale.type" select="$reference.locale.doc/*/local-name()"/>
    <xsl:apply-templates select="($target.locale.doc[*[local-name() = $locale.type]],$reference.locale.doc)[1]/node()"/>
  </xsl:template>
  
  <!-- push for further processing of reference locale entries (in order to force the same order to the target locale entries); group possibly superfluous entries (occurring only in target locale) at the end -->
  <xsl:template name="locale.process">
    <xsl:param name="reference.locale"/>
    <xsl:param name="target.locale.orphan.entries"/>
    <xsl:apply-templates select="$reference.locale/node()"/>
    <xsl:if test="$target.locale.orphan.entries">
      <xsl:value-of select="local:generate.indent($target.locale.orphan.entries[1])"/>
      <xsl:comment>possibly superfluous entries</xsl:comment>
      <xsl:apply-templates select="$target.locale.orphan.entries">
        <xsl:with-param name="indent" select="true()" tunnel="yes"/>
      </xsl:apply-templates>
    </xsl:if>
  </xsl:template>

  <!-- generate newline + tabs per nesting level -->
  <xsl:function name="local:generate.indent">
    <xsl:param name="node"/>
    <xsl:variable name="node.nesting.level" select="count($node/ancestor::*)"/>
    <xsl:value-of select="concat('&#xa;', for $i in $node.nesting.level return '&#x9;')"/>
  </xsl:function>
  
</xsl:stylesheet>
