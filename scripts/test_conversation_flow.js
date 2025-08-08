const { chromium } = require('playwright');

async function testConversationFlow() {
  const browser = await chromium.launch({ 
    headless: false,
    slowMo: 200
  });
  const page = await browser.newPage();
  
  console.log('🚀 Starting conversation flow test...\n');
  
  try {
    // Navigate to flow tester
    console.log('📍 Navigating to conversation flow tester...');
    await page.goto('http://localhost:9292/admin/test/flow');
    await page.waitForLoadState('networkidle');
    
    // Take initial screenshot
    await page.screenshot({ path: 'screenshots/flow-01-initial.png', fullPage: true });
    
    // Start a conversation with Buddy
    console.log('\n🤖 Starting conversation with Buddy...');
    console.log('───────────────────────────────────────');
    
    const conversations = [
      { persona: 'buddy', message: "Hey Buddy! What's your favorite thing about being an AI assistant?" },
      { persona: 'buddy', message: "That's interesting! Can you tell me a joke?" },
      { persona: 'buddy', message: "Haha! Do you have any advice for someone learning to code?" },
      { persona: 'jax', message: "Hey Jax, what's the vibe at your bar tonight?" },
      { persona: 'jax', message: "Sounds rowdy! What's your signature drink?" },
      { persona: 'lomi', message: "Hey Lomi! What's the tea today?" },
      { persona: 'lomi', message: "Werk! Any advice for being fabulous?" },
      { persona: 'zorp', message: "Yo Zorp! Ready to party?" },
      { persona: 'zorp', message: "What's your favorite party game?" }
    ];
    
    let currentPersona = 'buddy';
    let messageNum = 1;
    
    for (const conv of conversations) {
      // Switch persona if needed
      if (conv.persona !== currentPersona) {
        console.log(`\n🔄 Switching to ${conv.persona}...`);
        await page.click(`button[data-persona="${conv.persona}"]`);
        currentPersona = conv.persona;
        
        // Start new session for persona change
        const newSessionBtn = await page.$('button:has-text("Start New Session")');
        if (newSessionBtn) {
          await newSessionBtn.click();
          await page.waitForTimeout(500);
          
          // Confirm dialog
          page.once('dialog', async dialog => {
            await dialog.accept();
          });
        }
      }
      
      // Send message
      console.log(`\n[${messageNum}] You: "${conv.message}"`);
      await page.fill('#messageInput', conv.message);
      await page.press('#messageInput', 'Enter');
      
      // Wait for response
      await page.waitForTimeout(3000); // Give time for AI response
      
      // Try to get the response text (from last assistant message)
      const assistantMessages = await page.$$('.message.assistant .bubble');
      if (assistantMessages.length > 0) {
        const lastMessage = assistantMessages[assistantMessages.length - 1];
        const responseText = await lastMessage.textContent();
        console.log(`[${messageNum}] ${conv.persona}: "${responseText.substring(0, 100)}..."`);
      }
      
      // Check for tool calls
      const toolCalls = await page.$$('.tool-call');
      if (toolCalls.length > 0) {
        console.log(`    🔧 Tool calls detected: ${toolCalls.length}`);
      }
      
      // Check continue indicator
      const continueIndicator = await page.$('#continueIndicator');
      if (continueIndicator) {
        const continueText = await continueIndicator.textContent();
        if (continueText.includes('will continue')) {
          console.log(`    ↩️  Conversation will continue`);
        } else if (continueText.includes('ended')) {
          console.log(`    ⏹️  Conversation ended`);
        }
      }
      
      // Get stats
      const cost = await page.$eval('#totalCost', el => el.textContent);
      console.log(`    💰 Total cost so far: ${cost}`);
      
      messageNum++;
      
      // Take screenshot every 3 messages
      if (messageNum % 3 === 0) {
        await page.screenshot({ 
          path: `screenshots/flow-${String(messageNum).padStart(2, '0')}-conversation.png`, 
          fullPage: true 
        });
      }
    }
    
    // Final screenshot
    await page.screenshot({ path: 'screenshots/flow-final.png', fullPage: true });
    
    // Summary
    console.log('\n═══════════════════════════════════════');
    console.log('📊 Test Summary:');
    console.log('═══════════════════════════════════════');
    
    const finalStats = {
      messages: await page.$eval('#messageCount', el => el.textContent),
      cost: await page.$eval('#totalCost', el => el.textContent),
      sessionId: await page.$eval('#sessionId', el => el.textContent)
    };
    
    console.log(`✅ Sent ${messageNum - 1} messages`);
    console.log(`✅ ${finalStats.messages}`);
    console.log(`✅ Total cost: ${finalStats.cost}`);
    console.log(`✅ ${finalStats.sessionId}`);
    console.log(`✅ Tested all 4 personas`);
    
    // Check for any errors
    const errors = await page.$$('.message.error');
    if (errors.length > 0) {
      console.log(`⚠️  ${errors.length} errors encountered during conversation`);
    } else {
      console.log('✅ No errors encountered');
    }
    
    console.log('\n🎉 Conversation flow test complete!');
    console.log('Browser will remain open for inspection...');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error);
    await page.screenshot({ path: 'screenshots/flow-error.png', fullPage: true });
  }
}

// Run the test
testConversationFlow().catch(console.error);