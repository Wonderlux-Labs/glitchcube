const { chromium } = require('playwright');

async function testFlowPage() {
  const browser = await chromium.launch({ 
    headless: false,
    slowMo: 300  // Slow down to see what's happening
  });
  const page = await browser.newPage();
  
  console.log('🚀 Testing conversation flow page...\n');
  
  try {
    // Navigate to flow page
    console.log('📍 Navigating to flow page...');
    await page.goto('http://localhost:9292/admin/test/flow');
    await page.waitForLoadState('networkidle');
    
    // Take initial screenshot
    await page.screenshot({ path: 'screenshots/flow-test-01-initial.png', fullPage: true });
    
    // Send first message
    console.log('\n💬 Sending first message...');
    await page.fill('#messageInput', 'Hello Buddy! How are you today?');
    await page.press('#messageInput', 'Enter');
    
    // Wait for response to appear
    console.log('⏳ Waiting for response...');
    await page.waitForTimeout(5000); // Give time for the response
    
    // Check if response appeared
    const assistantMessages = await page.$$('.message.assistant');
    if (assistantMessages.length > 0) {
      console.log('✅ Response received!');
      
      // Get the response text
      const responseText = await assistantMessages[0].$eval('.bubble', el => el.textContent);
      console.log(`🤖 Buddy: "${responseText.substring(0, 100)}..."`);
      
      // Check metadata
      const metadata = await assistantMessages[0].$eval('.message-meta', el => el.textContent);
      console.log(`📊 Metadata: ${metadata}`);
    } else {
      console.log('⚠️ No response appeared in the UI');
    }
    
    // Check if button is re-enabled
    const isButtonDisabled = await page.$eval('#sendBtn', btn => btn.disabled);
    console.log(`🔘 Send button ${isButtonDisabled ? 'disabled' : 'enabled'}`);
    
    // Check session info
    const sessionInfo = await page.$eval('#sessionId', el => el.textContent);
    console.log(`📝 Session: ${sessionInfo}`);
    
    // Check cost
    const cost = await page.$eval('#totalCost', el => el.textContent);
    console.log(`💰 Cost: ${cost}`);
    
    // Check continue indicator
    const continueStatus = await page.$eval('#continueIndicator', el => el.textContent);
    console.log(`🔄 Continue status: ${continueStatus}`);
    
    // Send another message if enabled
    if (!isButtonDisabled) {
      console.log('\n💬 Sending follow-up message...');
      await page.fill('#messageInput', 'That sounds great! Tell me a joke.');
      await page.press('#messageInput', 'Enter');
      
      await page.waitForTimeout(5000);
      
      const newAssistantMessages = await page.$$('.message.assistant');
      if (newAssistantMessages.length > 1) {
        console.log('✅ Follow-up response received!');
      }
    }
    
    // Test persona switching
    console.log('\n🔄 Switching to Jax...');
    await page.click('button[data-persona="jax"]');
    await page.waitForTimeout(500);
    
    // Start new session
    await page.click('button:has-text("Start New Session")');
    page.once('dialog', async dialog => {
      console.log('📋 Confirming new session...');
      await dialog.accept();
    });
    await page.waitForTimeout(500);
    
    // Send message to Jax
    await page.fill('#messageInput', 'Hey Jax, what\'s your deal?');
    await page.press('#messageInput', 'Enter');
    
    await page.waitForTimeout(5000);
    
    // Final screenshot
    await page.screenshot({ path: 'screenshots/flow-test-02-final.png', fullPage: true });
    
    console.log('\n✅ Flow page test complete!');
    console.log('Browser will remain open for manual testing...');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error);
    await page.screenshot({ path: 'screenshots/flow-test-error.png', fullPage: true });
  }
}

// Run the test
testFlowPage().catch(console.error);