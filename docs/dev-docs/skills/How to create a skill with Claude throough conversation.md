# How to create a skill with Claude through conversation

## Table of contents

[Creating a skill through conversation](#h_31fb4ffa32)

[Skills you can build](#h_5688231990)

[What you can include within a skill](#h_37932beb75)

[Additional Resources](#h_bf474b2cfc)

With Skills, you are now able to teach Claude specific workflows, tools, and processes. When you create a skill, you're giving Claude a playbook it can reference whenever you need a particular type of help—whether that's generating reports in your company's format, cleaning and using data the way you normally do, or pulling and analyzing CRM data your way.

There are two paths for creating skills. You can create skills by writing the files yourself for full control over structure and implementation. See _[How to create custom skills](https://support.claude.com/en/articles/12512198-creating-custom-skills) and [Skills authoring best practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices)_ for that approach.

This guide focuses on the other path: creating skills through conversation with Claude. You describe your process naturally, and Claude handles the formatting and structure. This approach makes Skills accessible to anyone, regardless of technical background.

_New to skills? See [What are Skills](https://support.claude.com/en/articles/12512176-what-are-skills) and [Skills user guide](https://support.claude.com/en/articles/12580051-teach-claude-your-way-of-working-using-skills)_ to get started learning about Skills.

**Creating a skill through conversation**
-----------------------------------------

Creating a skill with Claude means having a conversation where you explain your approach and share any materials you want included. Claude translates this into a properly formatted skill that can work in future chats.

### **1\. Enable the skill-creator skill**

Go to `Settings` > `Capabilities` > `Skills` and turn on "skill-creator". This skill is what gives Claude the ability to build properly formatted skills for you. To learn more about the structure of a skill file, see [here](https://support.claude.com/en/articles/12512198-creating-custom-skills).

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781712103/95070063327be8b1c46103e5beb3/994ee3d8-3519-4342-a9dc-89aadb14545d?expires=1761561900&signature=28d662b50cf12cde3ec08596d4dda0b93dd4ca581d7b9477c3b67f4e5a57267c&req=dScvF85%2Fn4BfWvMW1HO4zY%2F055ZLrmlkhYiOv3782dk2p592QuhWqGAsZHdC%0AeDNK4%2F%2FJ8W2hDO9UY9s%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781712103/95070063327be8b1c46103e5beb3/994ee3d8-3519-4342-a9dc-89aadb14545d?expires=1761561900&signature=28d662b50cf12cde3ec08596d4dda0b93dd4ca581d7b9477c3b67f4e5a57267c&req=dScvF85%2Fn4BfWvMW1HO4zY%2F055ZLrmlkhYiOv3782dk2p592QuhWqGAsZHdC%0AeDNK4%2F%2FJ8W2hDO9UY9s%3D%0A)

### **2\. Start a conversation**

Open a new chat and say something like "I want to create a skill for quarterly business reviews" or "I need a skill that knows how to analyze customer feedback."

If you have materials that show your approach—templates you use, examples of work you're proud of, brand guidelines you follow, data files you reference—upload them. You can also mention any connected tools Claude should use. If you are unsure of what else to include, ask Claude for guidance.

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781712565/40d94d1311933626e6806483323b/fd9263c6-d6a0-41b6-97c0-faad55a5b0c3?expires=1761561900&signature=8b86dba27fff726d12f1f144a5d411b0ab3254fb68071b734ac34924ed3f4055&req=dScvF85%2Fn4RZXPMW1HO4zbjeIXA7JXvJL892nRaNsLzu8m126hJg1jJ6kW0g%0ASV9En%2F05sgEWnhjdG44%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781712565/40d94d1311933626e6806483323b/fd9263c6-d6a0-41b6-97c0-faad55a5b0c3?expires=1761561900&signature=8b86dba27fff726d12f1f144a5d411b0ab3254fb68071b734ac34924ed3f4055&req=dScvF85%2Fn4RZXPMW1HO4zbjeIXA7JXvJL892nRaNsLzu8m126hJg1jJ6kW0g%0ASV9En%2F05sgEWnhjdG44%3D%0A)

### **3\. Answer Claude's questions**

Claude will ask about your process. Provide enough detail that someone capable but unfamiliar could follow your approach.

You'll get questions about concrete usage ("Can you give examples of when you'd use this skill?") or about your process ("What makes output good for this type of work?").

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781724003/c7b6fc41f89347b432bbdf61cfe8/7f610b1d-002d-4fdd-a7d8-71fcb0796f9a?expires=1761561900&signature=2d5823aec30ad9fb607f51a6df88bfdcf86a623a78ea5a75698c3e5766b59e6e&req=dScvF858mYFfWvMW1HO4zb8c3Yr6%2F0D4RFsm81TO9AQE4LVPW%2FEflZTchKHE%0AJnCc1cxMTgRXrlUWxjk%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781724003/c7b6fc41f89347b432bbdf61cfe8/7f610b1d-002d-4fdd-a7d8-71fcb0796f9a?expires=1761561900&signature=2d5823aec30ad9fb607f51a6df88bfdcf86a623a78ea5a75698c3e5766b59e6e&req=dScvF858mYFfWvMW1HO4zb8c3Yr6%2F0D4RFsm81TO9AQE4LVPW%2FEflZTchKHE%0AJnCc1cxMTgRXrlUWxjk%3D%0A)

### **4\. Claude builds the Skill**

As you explain, Claude creates a SKILL.md file (the instruction file every skill needs), organizes any materials you've provided, and generates code for operations you've described that need to happen consistently. Claude packages everything into a ZIP file.

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781726214/d63daa444dc90e660ac7ef282d5d/5bd2c9e8-72f2-4506-be18-f0dccd1aa4e7?expires=1761561900&signature=7fa80c388a3d010d06f4bf9487d48c068ffadd1a6d2fca652409cd5f36cc60eb&req=dScvF858m4NeXfMW1HO4zZ5OtXvuhpXxWm7ij2EqW%2BRShKV%2FVaY7OF8cEIw%2F%0AcKA4As4%2B77GsYRQN2HY%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781726214/d63daa444dc90e660ac7ef282d5d/5bd2c9e8-72f2-4506-be18-f0dccd1aa4e7?expires=1761561900&signature=7fa80c388a3d010d06f4bf9487d48c068ffadd1a6d2fca652409cd5f36cc60eb&req=dScvF858m4NeXfMW1HO4zZ5OtXvuhpXxWm7ij2EqW%2BRShKV%2FVaY7OF8cEIw%2F%0AcKA4As4%2B77GsYRQN2HY%3D%0A)

### **5\. You activate and test it**

Download the ZIP file, then upload it in Settings > Capabilities > Skills. Your skill is now active.

Start a new conversation where this skill should apply. See if Claude recognizes the situation (you'll see "Using \[skill name\]" in Claude's thinking) and whether it produces what you need. If something's off, tell Claude what to adjust in the first conversation where you built the skill, and it will revise the skill. Download and add the revised skill to your library to test out the changes.

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781726036/d1c6af897f6ecce4343007537cbc/f27a8005-5bf5-4232-80a4-c90522bc06f4?expires=1761561900&signature=bdf0d62cccd2b098702b4e947831fcf1c664fe4ca2ce9edad6acb7c914d5bdcb&req=dScvF858m4FcX%2FMW1HO4zSVHBjM7fiLtfggwNrOfHKNhz%2FpZ1rHITgNl19bS%0A1dhNlz88B%2BWrxL2U%2BSQ%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781726036/d1c6af897f6ecce4343007537cbc/f27a8005-5bf5-4232-80a4-c90522bc06f4?expires=1761561900&signature=bdf0d62cccd2b098702b4e947831fcf1c664fe4ca2ce9edad6acb7c914d5bdcb&req=dScvF858m4FcX%2FMW1HO4zSVHBjM7fiLtfggwNrOfHKNhz%2FpZ1rHITgNl19bS%0A1dhNlz88B%2BWrxL2U%2BSQ%3D%0A)

**Skills you can build**
------------------------

You can build skills for a range of tasks. Skills can capture how your organization works, enable specialized expertise you don't personally have, or work together to handle complex workflows.

*   **CRM automation skill:** creates contacts, updates opportunities, maintains data standards to eliminate repetitive entry
    
*   **Legal contract review skill:** evaluates agreements against standard terms, identifies risky clauses, suggests protective language
    
*   **Sprint planning skill:** calculates team velocity, estimates work accounting for patterns, allocates capacity, generates planning docs
    
*   **SEO content skill:** analyzes opportunities, structures for search intent, optimizes while maintaining brand voice
    
*   **Music composition skill:** creates original tracks with realistic instruments, applies genre conventions, exports for production
    
*   **Report automation skill:** gathers monthly data, applies calculations, generates visualizations, formats in template, distributes to stakeholders
    
*   **Skill reviewer skill:** evaluates another skill's effectiveness, suggests improvements to instructions, identifies missing edge cases, recommends structure changes
    

**What you can include within a skill**
---------------------------------------

Skills bundle three types of content together—instructions, reference materials, and scripts. Knowing these components helps you articulate what you need when creating a skill with Claude.

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781727755/40d01224cb2a1653189d5211e731/380d5eae-c159-4643-80e3-ce1be19b6d57?expires=1761561900&signature=86a23296726e3cae6625a4d31b4c066a1c37b29a37b85cf7c482c0134d23e3e4&req=dScvF858moZaXPMW1HO4zRjaAo%2BbiwyUf1HwTII0D0GT174lTQUnHRbT7nMP%0AD%2FKq2xIwXl5gJSjiYEQ%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781727755/40d01224cb2a1653189d5211e731/380d5eae-c159-4643-80e3-ce1be19b6d57?expires=1761561900&signature=86a23296726e3cae6625a4d31b4c066a1c37b29a37b85cf7c482c0134d23e3e4&req=dScvF858moZaXPMW1HO4zRjaAo%2BbiwyUf1HwTII0D0GT174lTQUnHRbT7nMP%0AD%2FKq2xIwXl5gJSjiYEQ%3D%0A)

**Instructions —** Every skill needs a SKILL.md file that explains your process. When asking Claude to create a skill, describe your process for Claude to structure it into proper instructions. At the top of your [SKILL.md](http://skill.md) file, will be the skill's name and what it does. Claude scans this information first to decide whether or not to load and use the full skill during your conversations. Below that are clear instructions on how to do the task.

**Reference materials and assets —** Sometimes instructions alone aren't enough and Claude needs actual files to reference or use in the output. To include these, upload any relevant files or information when creating your Skill. Claude determines whether to embed guidance in the SKILL.md instructions or bundle it as a reference file.

*   **Brand assets:** font files, logos, color palettes, design templates
    
*   **Reference documents:** policy guides, workflow procedures, database schemas
    
*   **Templates:** spreadsheet with formulas, presentation layouts, document styles
    
*   **Data files:** CSV lookup tables, JSON configurations, pricing databases
    
*   **Media files:** audio samples, images, video clips
    

**Scripts —** These are executable code files that Claude can run to handle complex operations more reliably than instructions alone. You don't need to write these yourself. When you describe tasks that need scripts, Claude recognizes them and creates the code automatically. Examples include:

*   **Data work** for tasks like cleaning data, running calculations, and creating charts or dashboards
    

*   **Document work** to handle file processing tasks like batch editing and applying formatting
    
*   **Integrations** to connect your skill to other tools you use, such fetching data from external sources
    
*   **Media processing** to transform images, edit videos, and generate audio
    

_See available packages and capabilities._

**Additional Resources**
------------------------

### Getting started

*   [What are skills?](https://support.claude.com/en/articles/12512176-what-are-skills)
    
*   [Teach Claude your way of working using skills](https://support.claude.com/en/articles/12580051-teach-claude-your-way-of-working-using-skills)
    

### Going deeper

*   [Help Center: How to create custom skills](https://support.claude.com/en/articles/12512198-creating-custom-skills)
    
*   [Skill authoring best practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices)
    
*   [Skill cookbooks](https://github.com/anthropics/claude-cookbooks/tree/main/skills)
    
*   [Agent skills overview](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
    

* * *

Related Articles

[

Claude for Financial Services Overview

](https://support.claude.com/en/articles/12219959-claude-for-financial-services-overview)[

What are Skills?

](https://support.claude.com/en/articles/12512176-what-are-skills)[

Using Skills in Claude

](https://support.claude.com/en/articles/12512180-using-skills-in-claude)[

How to create custom Skills

](https://support.claude.com/en/articles/12512198-how-to-create-custom-skills)[

Teach Claude your way of working using skills

](https://support.claude.com/en/articles/12580051-teach-claude-your-way-of-working-using-skills)