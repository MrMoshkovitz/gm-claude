# Using Skills in Claude

## Table of contents

[Prerequisites](#h_4c9752a3a6)

[How to enable Skills](#h_c6008b84ad)

[Using Anthropic Skills](#h_ed1d052296)

[Adding and using custom skills](#h_a4222fa77b)

[How Claude uses Skills](#h_f2f6a9b6fc)

[Managing your Skills](#h_82b26f9db7)

[Enabling and disabling your Skills](#h_fa3f91f2a0)

[Privacy and security details](#h_2746475e70)

[Troubleshooting](#h_d2d3bae5f3)

[Best Practices](#h_0aba4bcd2b)

[Learn more about using Skills](#h_7654fe542e)

Skills extend Claude's capabilities by giving it access to specialized knowledge and workflows. This guide shows you how to enable, discover, and use Skills in Claude.

Skills are available as a feature preview for users on Pro, Max, Team, and Enterprise plans. This feature preview requires [code execution to be enabled](https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude#h_1c99382190). Skills are also available in beta for Claude Code users and for all API users using the code execution tool.

Prerequisites
-------------

**For Enterprise plans:** Owners must first enable both **Code execution and file creation** and **Skills** in [Admin settings > Capabilities](https://claude.ai/admin-settings/capabilities). Once enabled, individual members can toggle on example skills and upload their own in [Settings > Capabilities](https://preview.claude.ai/settings/capabilities).

**For Team plans:** This feature preview is enabled by default at the organization level. Once enabled, individual members can toggle on example skills and upload their own in [Settings > Capabilities](https://preview.claude.ai/settings/capabilities).

**For Max and Pro plans:** You can enable example skills and upload your own in [Settings > Capabilities](https://claude.ai/settings/capabilities).

How to enable Skills
--------------------

1.  Navigate to [Settings > Capabilities](https://claude.ai/settings/capabilities).
    
2.  Ensure that **Code execution and file creation** is enabled.
    
3.  Scroll to the **Skills** section.
    
4.  Toggle individual skills on or off as needed.
    
5.  To add custom skills, click "Upload skill" and upload a ZIP file containing your skill folder.
    

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781692976/3986c09def54467a7419e9cfd68e/8e4fa130-9c44-4067-bf12-520986644135?expires=1761561900&signature=78e2be0bcf51cbfedfc35fb231be809bb69921a24e3b42a43619492ee272ce3f&req=dScvF893n4hYX%2FMW1HO4zXi3CDPT8UlxmT2qapKX2kGbAWWDGzFbAEdGhuzF%0AejL2GM%2FNlimC6kf7UiA%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1781692976/3986c09def54467a7419e9cfd68e/8e4fa130-9c44-4067-bf12-520986644135?expires=1761561900&signature=78e2be0bcf51cbfedfc35fb231be809bb69921a24e3b42a43619492ee272ce3f&req=dScvF893n4hYX%2FMW1HO4zXi3CDPT8UlxmT2qapKX2kGbAWWDGzFbAEdGhuzF%0AejL2GM%2FNlimC6kf7UiA%3D%0A)

Using Anthropic Skills
----------------------

Anthropic provides several built-in skills that are available to all users, including:

*   Enhanced Excel spreadsheet creation and manipulation
    
*   Professional Word document creation
    
*   PowerPoint presentation generation
    
*   PDF creation and processing
    

With **Code execution and file creation** on, Claude will automatically use these tools when relevant. You don't need to explicitly invoke them—Claude determines when each skill is needed based on your request.

For example, if you ask Claude to "Create a PowerPoint presentation about Q3 results," Claude will automatically use the PowerPoint skill if the feature preview is enabled.

Adding and using custom skills
------------------------------

You can also create and upload your own skills to teach Claude your specific workflows:

1.  Create a skill following the skill structure (see [Creating Custom Skills](https://support.claude.com/en/articles/12512198-creating-custom-skills) for detailed instructions)
    
2.  Package your skill folder as a ZIP file
    
3.  Navigate to [Settings > Capabilities](https://claude.ai/settings/capabilities).
    
4.  In the Skills section, click "Upload skill"
    
5.  Upload your ZIP file
    
6.  Your skill will appear in your Skills list and can be toggled on or off
    

[![](https://downloads.intercomcdn.com/i/o/lupk8zyo/1782364123/a16cc51c623f6dc7ecef8974d629/98c13ee7-c134-4109-905c-384ab75a9ac6?expires=1761561900&signature=73773584dcb578ab28ac59f101029d1b522266a9b427731ae72fc7c635cd673d&req=dScvFMp4mYBdWvMW1HO4zRUki%2BD9hAec%2BfMHhPHscm5WoMtQbXPdREuKjVA0%0AbG6QAy1twHzOQEthjP8%3D%0A)](https://downloads.intercomcdn.com/i/o/lupk8zyo/1782364123/a16cc51c623f6dc7ecef8974d629/98c13ee7-c134-4109-905c-384ab75a9ac6?expires=1761561900&signature=73773584dcb578ab28ac59f101029d1b522266a9b427731ae72fc7c635cd673d&req=dScvFMp4mYBdWvMW1HO4zRUki%2BD9hAec%2BfMHhPHscm5WoMtQbXPdREuKjVA0%0AbG6QAy1twHzOQEthjP8%3D%0A)

**Note:** Custom skills you upload are private to your individual account. To share skills with your organization, you'll need to upload them separately or use the API.

How Claude uses Skills
----------------------

Claude automatically identifies and loads relevant skills based on your task. Refer to [What are Skills?](https://support.claude.com/en/articles/12512176-what-are-skills) to learn how this works.

Managing your Skills
--------------------

### Viewing your Skills

All your skills are listed in [Settings > Capabilities](https://claude.ai/settings/capabilities) under the Skills section. You can see:

*   Anthropic skills (created, tested, and maintained by Anthropic)
    
*   Custom skills you've uploaded
    
*   When each skill was enabled or uploaded
    
*   A brief description of what each skill does
    

Enabling and disabling your Skills
----------------------------------

Toggle any skill on or off using the switch next to it. Disabled skills won't be available to Claude.

### Removing custom Skills

To remove a custom skill you've uploaded:

1.  Navigate to [Settings > Capabilities](https://claude.ai/settings/capabilities).
    
2.  Find the skill in your Skills list.
    
3.  Click the delete or remove option.
    
4.  Confirm deletion.
    

Privacy and security details
----------------------------

Custom skills uploaded to Claude can’t currently be shared with other users; each individual wanting to use a skill on their account will need to upload it manually. Skills in Claude and the API operate in Claude's secure sandboxed environment with no data persistence between sessions.

Note that skills may include, or instruct Claude to install, third-party packages and software for Claude to use when completing a task. See [here](https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude#h_0ee9d698a1) for details on [Claude.ai](http://claude.ai)’s container environment and [here](https://docs.claude.com/en/docs/agents-and-tools/tool-use/code-execution-tool#containers) for API’s container environment.

### What are the primary risks of using Skills?

The most significant risks are prompt injection, which allows Claude to be manipulated to execute unintended actions, and data exfiltration, caused by malicious package code or prompt-injected data leaks. We’ve implemented several mitigations to these risks. Refer to [our security considerations for code execution](https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude#h_0ee9d698a1) for more information.

**Important:** Only install skills only from trusted sources.

When installing a skill from a less-trusted source, thoroughly audit it before use. Start by reading the contents of the files bundled in the skill to understand what it does, paying particular attention to code dependencies and bundled resources like images or scripts. Similarly, pay attention to instructions or code within the skill that instruct Claude to connect to potentially untrusted external network sources.

Troubleshooting
---------------

### Skills section not visible

Ensure code execution is enabled in [Settings > Capabilities](https://claude.ai/settings/capabilities). Skills require the code execution environment to function.

### Claude isn’t using a Skill

*   Verify the Skill is toggled on in [Settings > Capabilities](https://claude.ai/settings/capabilities).
    
*   Check that the Skill's description field clearly explains when it should be used.
    
*   Ensure the Skill's instructions are clear and well-structured.
    
*   Try being more explicit in your request (e.g., "Use my brand guidelines skill to create a presentation").
    

### Upload errors

Common reasons for upload failures:

*   ZIP file exceeds size limits
    
*   Skill folder name doesn't match the skill name
    
*   Missing required Skill.md file
    
*   Invalid characters in skill name or description
    

### Skills greyed out

If Skills appear greyed out, code execution or Skills may be disabled at the organization level (for Team and Enterprise plans) or individually. Check with your organization's Owner or make sure to enable code execution in your settings.

Best Practices
--------------

### Start Simple

Begin with Anthropic's pre-built Skills to understand how they work before creating custom skills.

### Be Specific

Write clear descriptions when writing custom skills. A specific description tells Claude when to invoke your skill.

### Test Your Skills

After uploading a custom skill, test it with a few different prompts to ensure it works as expected.

### Organize by Purpose

Create separate skills for different purposes rather than a single skill that’s meant to do everything.

Learn more about using Skills
-----------------------------

Refer to [Teach Claude your way of working using Skills](https://support.claude.com/en/articles/12580051-teach-claude-your-way-of-working-using-skills) for more information and video demonstrations.

* * *

Related Articles

[

Create and edit files with Claude

](https://support.claude.com/en/articles/12111783-create-and-edit-files-with-claude)[

What are Skills?

](https://support.claude.com/en/articles/12512176-what-are-skills)[

How to create custom Skills

](https://support.claude.com/en/articles/12512198-how-to-create-custom-skills)[

How to create a skill with Claude through conversation

](https://support.claude.com/en/articles/12599426-how-to-create-a-skill-with-claude-through-conversation)[

How to use the single-cell-rna-qc skill with Claude

](https://support.claude.com/en/articles/12621831-how-to-use-the-single-cell-rna-qc-skill-with-claude)